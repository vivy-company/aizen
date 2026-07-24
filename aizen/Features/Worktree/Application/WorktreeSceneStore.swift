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

    @Published private(set) var fileBrowserStore: FileBrowserStore?
    @Published private(set) var browserSessionStore: BrowserSessionStore?
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

    /// Lazily creates the store a pane kind depends on. Called when a pane of
    /// that kind enters the visible layout.
    func ensureStore(for kind: PaneKind) {
        switch kind {
        case .files:
            if fileBrowserStore == nil, worktree.path != nil {
                fileBrowserStore = FileBrowserStore(worktree: worktree, context: viewContext)
            }
            syncFileBrowserVisibility()
        case .browser:
            if browserSessionStore == nil {
                browserSessionStore = BrowserSessionStore(viewContext: viewContext, worktree: worktree)
            }
        case .terminal, .chat, .gitDiff, .empty:
            break
        }
        trackOpenedSurfaceIfNeeded(kind)
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
            fileBrowserStore?.setVisible(false)
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
        fileBrowserStore?.setVisible(false)
        runtime.detachDetail()
        workspace.persistTreeNow()
        workspace.handleDisappear()
        browserSessionStore?.clearWarmWebViews()
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
        let hasVisibleFilePane = workspace.tree.allPanes().contains { $0.kind == .files }
        fileBrowserStore?.setVisible(isSceneActive && hasVisibleFilePane)
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
