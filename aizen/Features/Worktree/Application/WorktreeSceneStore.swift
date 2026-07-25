//
//  WorktreeSceneStore.swift
//  aizen
//
//  Store ownership for a single worktree detail surface: the workspace
//  layout store plus per-feature stores panes bind to.
//

import Combine
import CoreData
import Foundation

@MainActor
final class WorktreeSceneStore: ObservableObject, Identifiable {
    let id: NSManagedObjectID
    let worktree: Worktree
    let repositoryManager: WorkspaceRepositoryStore
    let detailStore: WorktreeDetailStore
    let runtime: WorktreeRuntime
    let workspace: WorkspaceStore

    @Published private var fileBrowserStoresById: [UUID: FileBrowserStore] = [:]
    @Published private var browserSessionStoresById: [UUID: BrowserSessionStore] = [:]
    @Published var lastOpenedApp: DetectedApp?

    private let viewContext: NSManagedObjectContext
    private var chatStoresById: [UUID: ChatSessionStore] = [:]
    private var chatStoreOrder: [UUID] = []
    private let maxWarmChatStores = 3
    private var detailActivationTask: Task<Void, Never>?
    private var isSceneActive = false
    private var detailAttached = false
    private var pendingShowXcode = false
    private var trackedOpenedPaneKinds: Set<PaneKind> = []
    private let detailActivationDelay = Duration.milliseconds(140)

    init(
        worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        viewContext: NSManagedObjectContext
    ) {
        self.id = worktree.objectID
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.detailStore = WorktreeDetailStore(worktree: worktree, repositoryManager: repositoryManager)
        self.runtime = WorktreeRuntimeCoordinator.shared.runtime(for: worktree.path ?? "")
        self.viewContext = viewContext
        self.workspace = WorkspaceStore(worktree: worktree, viewContext: viewContext)
    }

    // MARK: - Feature stores

    /// Lazily creates the store a pane depends on. File and browser stores are
    /// keyed by the pane's persisted session identity, never by worktree.
    func ensureStore(for pane: WorkspacePane) {
        switch pane.kind {
        case .files:
            if let sessionId = pane.sessionId,
               fileBrowserStoresById[sessionId] == nil,
               let session = workspace.filePaneSession(withId: sessionId) {
                fileBrowserStoresById[sessionId] = FileBrowserStore(
                    worktree: worktree,
                    context: viewContext,
                    session: session
                )
            }
            syncFileBrowserVisibility()
        case .browser:
            if let sessionId = pane.sessionId,
               browserSessionStoresById[sessionId] == nil {
                browserSessionStoresById[sessionId] = BrowserSessionStore(
                    viewContext: viewContext,
                    worktree: worktree,
                    workspaceSessionId: sessionId
                )
            }
        case .terminal, .chat, .gitDiff, .empty:
            break
        }
        trackOpenedSurfaceIfNeeded(pane.kind)
    }

    func synchronizePaneStores(with panes: [WorkspacePane]) {
        for pane in panes {
            ensureStore(for: pane)
        }

        let visibleFileSessionIds = Set(panes.compactMap { $0.kind == .files ? $0.sessionId : nil })
        for (sessionId, store) in fileBrowserStoresById {
            store.setVisible(isSceneActive && visibleFileSessionIds.contains(sessionId))
            if !visibleFileSessionIds.contains(sessionId) {
                store.flushSessionSave()
            }
        }
        fileBrowserStoresById = fileBrowserStoresById.filter {
            visibleFileSessionIds.contains($0.key)
        }

        let visibleBrowserSessionIds = Set(panes.compactMap { $0.kind == .browser ? $0.sessionId : nil })
        for (sessionId, store) in browserSessionStoresById where !visibleBrowserSessionIds.contains(sessionId) {
            store.flushPendingSave()
            store.clearWarmWebViews()
        }
        browserSessionStoresById = browserSessionStoresById.filter {
            visibleBrowserSessionIds.contains($0.key)
        }
    }

    func fileBrowserStore(for pane: WorkspacePane) -> FileBrowserStore? {
        guard pane.kind == .files, let sessionId = pane.sessionId else { return nil }
        return fileBrowserStoresById[sessionId]
    }

    func browserSessionStore(for pane: WorkspacePane) -> BrowserSessionStore? {
        guard pane.kind == .browser, let sessionId = pane.sessionId else { return nil }
        return browserSessionStoresById[sessionId]
    }

    @discardableResult
    func revealBrowserSession(_ sessionId: UUID) -> Bool {
        guard workspace.revealBrowserSession(sessionId),
              let pane = workspace.focusedPane,
              pane.kind == .browser else {
            return false
        }

        ensureStore(for: pane)
        browserSessionStore(for: pane)?.selectSession(sessionId)
        return true
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

    // MARK: - Presentation lifecycle

    func updatePresentation(isActive: Bool, showXcode: Bool) {
        pendingShowXcode = showXcode

        guard isActive else {
            isSceneActive = false
            cancelActivationTasks()
            detailAttached = false
            fileBrowserStoresById.values.forEach { $0.setVisible(false) }
            runtime.detachDetail()
            return
        }

        isSceneActive = true
        syncFileBrowserVisibility()

        if detailAttached {
            runtime.updateDetailOptions(showXcode: showXcode)
        } else {
            scheduleDetailActivation()
        }
    }

    func prepareForEviction() {
        cancelActivationTasks()
        isSceneActive = false
        detailAttached = false
        fileBrowserStoresById.values.forEach { $0.setVisible(false) }
        runtime.detachDetail()
        workspace.persistTreeNow()
        workspace.handleDisappear()
        fileBrowserStoresById.values.forEach { $0.flushSessionSave() }
        browserSessionStoresById.values.forEach {
            $0.flushPendingSave()
            $0.clearWarmWebViews()
        }
        fileBrowserStoresById.removeAll()
        browserSessionStoresById.removeAll()
        chatStoresById.removeAll()
        chatStoreOrder.removeAll()
    }

    private func trackOpenedSurfaceIfNeeded(_ kind: PaneKind) {
        guard !trackedOpenedPaneKinds.contains(kind) else { return }

        switch kind {
        case .files:
            trackedOpenedPaneKinds.insert(kind)
            Analytics.shared.track(.fileBrowserOpened(entryPoint: .worktree))
        case .browser:
            trackedOpenedPaneKinds.insert(kind)
            Analytics.shared.track(.browserOpened(entryPoint: .worktree))
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

    private func cancelActivationTasks() {
        detailActivationTask?.cancel()
        detailActivationTask = nil
    }

    private func syncFileBrowserVisibility() {
        let visibleSessionIds = Set(workspace.tree.allPanes().compactMap {
            $0.kind == .files ? $0.sessionId : nil
        })
        for (sessionId, store) in fileBrowserStoresById {
            store.setVisible(isSceneActive && visibleSessionIds.contains(sessionId))
        }
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
