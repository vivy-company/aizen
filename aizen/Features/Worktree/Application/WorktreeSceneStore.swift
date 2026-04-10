//
//  WorktreeSceneStore.swift
//  aizen
//
//  Warm scene ownership for a single worktree detail surface.
//

import Combine
import CoreData
import Foundation

@MainActor
final class WorktreeSceneStore: ObservableObject, Identifiable {
    let id: NSManagedObjectID
    let worktree: Worktree
    let repositoryManager: WorkspaceRepositoryStore
    let tabStateManager: WorktreeTabStateStore
    let detailStore: WorktreeDetailStore
    let runtime: WorktreeRuntime

    @Published private(set) var fileBrowserStore: FileBrowserStore?
    @Published private(set) var browserSessionStore: BrowserSessionStore?
    @Published private(set) var warmedTabIds: Set<String> = []
    @Published var selectedTab = "chat"
    @Published var lastOpenedApp: DetectedApp?

    var hasLoadedTabState = false

    private let viewContext: NSManagedObjectContext
    private var chatStoresById: [UUID: ChatSessionStore] = [:]
    private var chatStoreOrder: [UUID] = []
    private let maxWarmChatStores = 3
    private var detailActivationTask: Task<Void, Never>?
    private var tabPrewarmTask: Task<Void, Never>?
    private var isSceneActive = false
    private var detailAttached = false
    private var activeVisibleTabIds: [String] = []
    private var pendingShowXcode = false
    private let detailActivationDelay = Duration.milliseconds(140)
    private let tabPrewarmDelay = Duration.milliseconds(180)

    init(
        worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        tabStateManager: WorktreeTabStateStore,
        viewContext: NSManagedObjectContext
    ) {
        self.id = worktree.objectID
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.tabStateManager = tabStateManager
        self.detailStore = WorktreeDetailStore(worktree: worktree, repositoryManager: repositoryManager)
        self.runtime = WorktreeRuntimeCoordinator.shared.runtime(for: worktree.path ?? "")
        self.viewContext = viewContext
    }

    func restorePersistedStateIfNeeded(defaultTab: String) {
        guard !hasLoadedTabState else { return }

        if let worktreeId = worktree.id,
           tabStateManager.hasStoredState(for: worktreeId) {
            let state = tabStateManager.getState(for: worktreeId)
            selectTab(state.viewType)
            detailStore.selectedChatSessionId = state.chatSessionId
            detailStore.selectedTerminalSessionId = state.terminalSessionId
            detailStore.selectedBrowserSessionId = state.browserSessionId
            detailStore.selectedFileSessionId = state.fileSessionId
        } else {
            selectTab(defaultTab)
        }

        hasLoadedTabState = true
    }

    func selectTab(_ tabId: String) {
        warmedTabIds.insert(tabId)
        warmStoreIfNeeded(for: tabId)
        selectedTab = tabId
        syncFeatureVisibility()
    }

    func isTabWarm(_ tabId: String) -> Bool {
        warmedTabIds.contains(tabId)
    }

    func prewarmTabs(_ tabIds: [String]) {
        for tabId in tabIds {
            guard !tabId.isEmpty else { continue }
            warmedTabIds.insert(tabId)
            warmStoreIfNeeded(for: tabId)
        }
    }

    func updatePresentation(isActive: Bool, visibleTabIds: [String], showXcode: Bool) {
        pendingShowXcode = showXcode
        activeVisibleTabIds = visibleTabIds

        guard isActive else {
            isSceneActive = false
            cancelActivationTasks()
            detailAttached = false
            syncFeatureVisibility()
            runtime.detachDetail()
            return
        }

        isSceneActive = true
        warmStoreIfNeeded(for: selectedTab)
        syncFeatureVisibility()
        scheduleTabPrewarm()

        if detailAttached {
            runtime.updateDetailOptions(showXcode: showXcode)
        } else {
            scheduleDetailActivation()
        }
    }

    func saveSelectedTabIfNeeded() {
        guard hasLoadedTabState, let worktreeId = worktree.id else { return }
        tabStateManager.saveViewType(selectedTab, for: worktreeId)
    }

    func saveSessionId(_ sessionId: UUID?, for tabId: String) {
        guard let worktreeId = worktree.id else { return }
        tabStateManager.saveSessionId(sessionId, for: tabId, worktreeId: worktreeId)
    }

    func prepareForEviction() {
        cancelActivationTasks()
        isSceneActive = false
        detailAttached = false
        syncFeatureVisibility()
        runtime.detachDetail()
        browserSessionStore?.clearWarmWebViews()
        chatStoresById.removeAll()
        chatStoreOrder.removeAll()
    }

    func chatStore(for session: ChatSession) -> ChatSessionStore {
        guard let sessionId = session.id else {
            return ChatSessionStore(
                worktree: worktree,
                session: session,
                sessionManager: ChatSessionRegistry.shared,
                viewContext: viewContext
            )
        }

        if let existingStore = chatStoresById[sessionId] {
            touchChatStore(sessionId)
            return existingStore
        }

        let newStore = ChatSessionStore(
            worktree: worktree,
            session: session,
            sessionManager: ChatSessionRegistry.shared,
            viewContext: viewContext
        )
        chatStoresById[sessionId] = newStore
        touchChatStore(sessionId)
        evictChatStoresIfNeeded()
        return newStore
    }

    private func warmStoreIfNeeded(for tabId: String) {
        switch tabId {
        case "files":
            if fileBrowserStore == nil, worktree.path != nil {
                fileBrowserStore = FileBrowserStore(worktree: worktree, context: viewContext)
            }
        case "browser":
            if browserSessionStore == nil {
                browserSessionStore = BrowserSessionStore(viewContext: viewContext, worktree: worktree)
            }
        default:
            break
        }
    }

    private func scheduleDetailActivation() {
        detailActivationTask?.cancel()
        let activationDelay = detailActivationDelay
        detailActivationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: activationDelay)
            } catch {
                return
            }

            guard let self, self.isSceneActive, !Task.isCancelled else { return }
            self.runtime.attachDetail(showXcode: self.pendingShowXcode)
            self.detailAttached = true
            self.detailActivationTask = nil
        }
    }

    private func scheduleTabPrewarm() {
        tabPrewarmTask?.cancel()
        let tabIdsToPrewarm = activeVisibleTabIds.filter { $0 != selectedTab }
        guard !tabIdsToPrewarm.isEmpty else { return }
        let prewarmDelay = tabPrewarmDelay

        tabPrewarmTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: prewarmDelay)
            } catch {
                return
            }

            guard let self, self.isSceneActive, !Task.isCancelled else { return }
            self.prewarmTabs(tabIdsToPrewarm)
            self.tabPrewarmTask = nil
        }
    }

    private func syncFeatureVisibility() {
        fileBrowserStore?.setVisible(isSceneActive && selectedTab == "files")
    }

    private func cancelActivationTasks() {
        detailActivationTask?.cancel()
        detailActivationTask = nil
        tabPrewarmTask?.cancel()
        tabPrewarmTask = nil
    }

    private func touchChatStore(_ sessionId: UUID) {
        chatStoreOrder.removeAll { $0 == sessionId }
        chatStoreOrder.append(sessionId)
    }

    private func evictChatStoresIfNeeded() {
        while chatStoresById.count > maxWarmChatStores,
              let oldestSessionId = chatStoreOrder.first {
            chatStoreOrder.removeFirst()
            chatStoresById.removeValue(forKey: oldestSessionId)
        }
    }
}
