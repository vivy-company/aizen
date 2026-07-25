//
//  WorkspaceStore+Mutations.swift
//  aizen
//
//  Split-tree mutations and per-kind pane session provisioning/teardown.
//

import CoreData
import Foundation

@MainActor
extension WorkspaceStore {
    // MARK: - Split / resize

    func splitFocusedPane(direction: SplitDirection, insertion: WorkspaceSplitNode.SplitInsertion) {
        guard let source = focusedPane else { return }
        let newPane = makePane(kind: source.kind, inheritingFrom: source)
        setTree(tree.splitting(paneId: source.id, direction: direction, insertion: insertion, newPane: newPane))
        focusPane(newPane.id)
        focusRequestVersion += 1
    }

    func resizeSplit(at path: SplitPath, to ratio: Double) {
        setTree(tree.updatingRatio(at: path, to: ratio))
    }

    func equalize() {
        setTree(tree.equalized())
    }

    // MARK: - Replace / assign kind

    /// Turns a pane into the given kind in place, provisioning a session when
    /// the kind needs one and tearing down the previous content's runtime.
    func replacePane(_ paneId: String, with kind: PaneKind) {
        guard let existing = tree.pane(withId: paneId), existing.kind != kind else { return }

        teardownPaneRuntime(existing)

        let replacement = makePane(kind: kind, inheritingFrom: nil, reusingId: paneId)
        setTree(tree.updatingPane(paneId) { pane in
            pane.kind = replacement.kind
            pane.sessionId = replacement.sessionId
        })
        focusPane(paneId)
        focusRequestVersion += 1
    }

    /// Replaces the pane with a fresh chat session owned by the selected
    /// agent. This also handles chat-to-chat replacement, where the pane kind
    /// itself does not change.
    func replacePane(_ paneId: String, withChatAgent agentId: String) {
        guard AgentCatalogStore.shared.enabledAgents.contains(where: { $0.id == agentId }),
              let existing = tree.pane(withId: paneId),
              currentChatAgentId(for: existing) != agentId,
              let session = createChatSession(agentId: agentId) else {
            return
        }

        teardownPaneRuntime(existing)
        setTree(tree.updatingPane(paneId) { pane in
            pane.kind = .chat
            pane.sessionId = session.id
        })
        focusPane(paneId)
        focusRequestVersion += 1
    }

    // MARK: - Close

    func requestCloseFocusedPane() {
        guard let pane = focusedPane else { return }
        requestClosePane(pane.id)
    }

    func requestClosePane(_ paneId: String) {
        guard let pane = tree.pane(withId: paneId) else { return }
        if pane.kind == .terminal,
           let sessionId = pane.sessionId,
           TerminalRuntimeStore.shared.paneHasRunningProcess(for: sessionId, paneId: pane.id) {
            pendingCloseConfirmationPaneId = paneId
            return
        }
        closePane(paneId)
    }

    func confirmPendingClose() {
        guard let paneId = pendingCloseConfirmationPaneId else { return }
        pendingCloseConfirmationPaneId = nil
        closePane(paneId)
    }

    func closePane(_ paneId: String) {
        guard let pane = tree.pane(withId: paneId) else { return }
        guard !closingPaneIds.contains(paneId) else { return }
        closingPaneIds.insert(paneId)
        defer { closingPaneIds.remove(paneId) }

        paneVoiceRecordingStates.removeValue(forKey: paneId)

        if let newTree = tree.removingPane(paneId) {
            setTree(newTree)
            teardownPaneRuntime(pane)
            if focusedPaneId == paneId {
                focusPane(newTree.allPaneIds().first ?? "")
                focusRequestVersion += 1
            }
        } else {
            // Last pane in the layout: keep the layout, reset to an empty pane.
            teardownPaneRuntime(pane)
            let empty = WorkspacePane(kind: .empty)
            setTree(.leaf(empty))
            focusPane(empty.id)
        }
    }

    func handleTerminalProcessExit(paneId: String) {
        guard tree.pane(withId: paneId) != nil else { return }
        guard !closingPaneIds.contains(paneId) else { return }
        closePane(paneId)
    }

    /// New layout tab seeded with a pane of the given kind. Terminal tabs get
    /// their own fresh session instead of joining the active layout's.
    func addLayout(kind: PaneKind) {
        let pane: WorkspacePane
        switch kind {
        case .terminal:
            let session = TerminalSession(context: viewContext)
            session.id = UUID()
            session.createdAt = Date()
            session.worktree = worktree
            saveContext()
            pane = WorkspacePane(kind: .terminal, sessionId: session.id)
        case .chat:
            pane = makePane(kind: .chat, inheritingFrom: nil)
        case .files, .browser:
            pane = makePane(kind: kind, inheritingFrom: nil)
        case .gitDiff, .empty:
            pane = WorkspacePane(kind: kind)
        }
        addLayout(tree: .leaf(pane))
    }

    // MARK: - Pane provisioning

    /// Builds a pane of the given kind, creating or reusing backing sessions.
    /// `inheritingFrom` shares session scope where it makes sense (a terminal
    /// split joins the source pane's TerminalSession).
    func makePane(kind: PaneKind, inheritingFrom source: WorkspacePane?, reusingId paneId: String? = nil) -> WorkspacePane {
        let id = paneId ?? UUID().uuidString
        switch kind {
        case .terminal:
            let sessionId: UUID?
            if let source, source.kind == .terminal, let sourceSessionId = source.sessionId {
                sessionId = sourceSessionId
            } else {
                sessionId = findOrCreateTerminalSession()?.id
            }
            return WorkspacePane(id: id, kind: .terminal, sessionId: sessionId)

        case .chat:
            return WorkspacePane(id: id, kind: .chat, sessionId: createChatSession(agentId: defaultAgentId())?.id)

        case .files:
            return WorkspacePane(id: id, kind: .files, sessionId: createFilePaneSession()?.id)

        case .browser:
            return WorkspacePane(id: id, kind: .browser, sessionId: createBrowserWorkspaceSessionId())

        case .gitDiff, .empty:
            return WorkspacePane(id: id, kind: kind)
        }
    }

    func terminalSession(withId id: UUID) -> TerminalSession? {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.first { $0.id == id }
    }

    func chatSession(withId id: UUID) -> ChatSession? {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.first { $0.id == id }
    }

    func filePaneSession(withId id: UUID) -> FilePaneSession? {
        let sessions = (worktree.filePaneSessions as? Set<FilePaneSession>) ?? []
        return sessions.first { $0.id == id }
    }

    private func findOrCreateTerminalSession() -> TerminalSession? {
        // Reuse the session backing another terminal pane in this layout so
        // panes stay grouped; otherwise create a fresh one.
        if let existingId = tree.allPanes().first(where: { $0.kind == .terminal })?.sessionId,
           let existing = terminalSession(withId: existingId) {
            return existing
        }

        let session = TerminalSession(context: viewContext)
        session.id = UUID()
        session.createdAt = Date()
        session.worktree = worktree
        saveContext()
        return session
    }

    private func createChatSession(agentId: String) -> ChatSession? {
        let session = ChatSession(context: viewContext)
        session.id = UUID()
        session.agentName = agentId
        session.title = AgentRegistry.shared.getMetadata(for: agentId)?.name ?? agentId.capitalized
        session.archived = false
        session.createdAt = Date()
        session.worktree = worktree
        saveContext()
        return session
    }

    private func currentChatAgentId(for pane: WorkspacePane) -> String? {
        guard pane.kind == .chat,
              let sessionId = pane.sessionId else {
            return nil
        }
        return chatSession(withId: sessionId)?.agentName
    }

    private func createFilePaneSession() -> FilePaneSession? {
        let existingSessions = (worktree.filePaneSessions as? Set<FilePaneSession>) ?? []
        let session = FilePaneSession(context: viewContext)
        session.id = UUID()
        session.currentPath = worktree.path
        session.setValue([], forKey: "expandedPaths")
        session.setValue([], forKey: "openFilesPaths")
        session.worktree = worktree

        if let legacy = worktree.fileBrowserSession {
            if existingSessions.isEmpty {
                session.currentPath = legacy.currentPath ?? worktree.path
                session.expandedPaths = legacy.expandedPaths
                session.openFilesPaths = legacy.openFilesPaths
                session.selectedFilePath = legacy.selectedFilePath
            }
            viewContext.delete(legacy)
        }

        saveContext()
        return session
    }

    private func createBrowserWorkspaceSessionId(claimingLegacySessions: Bool = false) -> UUID {
        let workspaceSessionId = UUID()
        guard claimingLegacySessions else { return workspaceSessionId }

        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        for session in sessions where session.workspaceSessionId == nil {
            session.workspaceSessionId = workspaceSessionId
        }
        saveContext()
        return workspaceSessionId
    }

    func provisioningMissingSessionBindings(in node: WorkspaceSplitNode) -> WorkspaceSplitNode {
        var result = node
        var canClaimLegacyBrowserSessions = !allPersistedPanes().contains {
            $0.kind == .browser && $0.sessionId != nil
        }

        for pane in node.allPanes() {
            switch pane.kind {
            case .files:
                if let sessionId = pane.sessionId,
                   filePaneSession(withId: sessionId) != nil {
                    continue
                }
                let sessionId = createFilePaneSession()?.id
                result = result.updatingPane(pane.id) { $0.sessionId = sessionId }

            case .browser:
                guard pane.sessionId == nil else { continue }
                let sessionId = createBrowserWorkspaceSessionId(
                    claimingLegacySessions: canClaimLegacyBrowserSessions
                )
                canClaimLegacyBrowserSessions = false
                result = result.updatingPane(pane.id) { $0.sessionId = sessionId }

            case .terminal, .chat, .gitDiff, .empty:
                break
            }
        }
        return result
    }

    private func allPersistedPanes() -> [WorkspacePane] {
        layouts.flatMap { layout in
            return layout.treeJSON.flatMap(WorkspaceLayoutCodec.decode)?.allPanes() ?? []
        }
    }

    private func defaultAgentId() -> String {
        if let stored = UserDefaults.standard.string(forKey: "defaultACPAgent"),
           AgentRegistry.shared.getEnabledAgents().contains(where: { $0.id == stored }) {
            return stored
        }
        return AgentRegistry.shared.getEnabledAgents().first?.id ?? AgentRegistry.defaultAgentID
    }

    // MARK: - Teardown

    /// Releases runtime owned by a pane that left the tree. Sessions shared
    /// with panes that still exist (in any layout) are left alone.
    func teardownPaneRuntime(_ pane: WorkspacePane) {
        switch pane.kind {
        case .terminal:
            guard let sessionId = pane.sessionId else { return }
            TerminalRuntimeStore.shared.removeTerminal(for: sessionId, paneId: pane.id)
            let paneId = pane.id
            Task {
                await TmuxSessionRuntime.shared.killSession(paneId: paneId)
            }
            if !sessionReferencedByAnyPane(sessionId, excludingPaneId: pane.id),
               let session = terminalSession(withId: sessionId) {
                viewContext.delete(session)
                saveContext()
            }

        case .chat:
            guard let sessionId = pane.sessionId else { return }
            if !sessionReferencedByAnyPane(sessionId, excludingPaneId: pane.id) {
                ChatSessionRegistry.shared.removeAgentSession(for: sessionId)
                if let session = chatSession(withId: sessionId), !session.isDeleted {
                    session.archived = true
                    saveContext()
                }
            }

        case .files:
            guard let sessionId = pane.sessionId else { return }
            if !sessionReferencedByAnyPane(sessionId, excludingPaneId: pane.id),
               let session = filePaneSession(withId: sessionId) {
                viewContext.delete(session)
                saveContext()
            }

        case .browser:
            guard let workspaceSessionId = pane.sessionId else { return }
            if !sessionReferencedByAnyPane(workspaceSessionId, excludingPaneId: pane.id) {
                let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
                for session in sessions where session.workspaceSessionId == workspaceSessionId {
                    viewContext.delete(session)
                }
                saveContext()
            }

        case .gitDiff, .empty:
            break
        }
    }

    /// Whether any pane across all layouts still references the session.
    func sessionReferencedByAnyPane(_ sessionId: UUID, excludingPaneId: String) -> Bool {
        for layout in layouts {
            let layoutTree = layout.id == activeLayoutId
                ? tree
                : layout.treeJSON.flatMap(WorkspaceLayoutCodec.decode)
            guard let layoutTree else { continue }
            for pane in layoutTree.allPanes()
            where pane.sessionId == sessionId && pane.id != excludingPaneId {
                return true
            }
        }
        return false
    }

    // MARK: - Legacy migration

    /// One-time conversion of the pre-workspace state: each TerminalSession's
    /// split tree becomes a layout tab (pane ids preserved so tmux sessions and
    /// surface caches keep working); the latest chat, browser tabs, and files
    /// become layouts of their kind.
    func migrateLegacyStateIfNeeded() {
        let existing = (worktree.layouts as? Set<WorktreeLayout>) ?? []
        guard existing.isEmpty else { return }

        var order: Int64 = 0

        func insertLayout(name: String?, tree: WorkspaceSplitNode, focusedPaneId: String?) {
            let layout = WorktreeLayout(context: viewContext)
            layout.id = UUID()
            layout.name = name
            layout.order = order
            layout.createdAt = Date()
            layout.treeJSON = WorkspaceLayoutCodec.encode(tree)
            layout.focusedPaneId = focusedPaneId
            layout.worktree = worktree
            if order < Int64.max {
                order += 1
            }
        }

        let terminalSessions = ((worktree.terminalSessions as? Set<TerminalSession>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

        for session in terminalSessions {
            guard let sessionId = session.id else { continue }
            var sessionTree: WorkspaceSplitNode
            if let json = session.splitLayout, let decoded = WorkspaceLayoutCodec.decode(json) {
                sessionTree = decoded
            } else {
                sessionTree = TerminalLayoutDefaults.defaultLayout(
                    paneId: TerminalLayoutDefaults.paneId(sessionId: sessionId, focusedPaneId: session.focusedPaneId)
                )
            }
            for pane in sessionTree.allPanes() {
                sessionTree = sessionTree.updatingPane(pane.id) { $0.sessionId = sessionId }
            }
            insertLayout(name: session.title, tree: sessionTree, focusedPaneId: session.focusedPaneId)
        }

        let chatSessions = ((worktree.chatSessions as? Set<ChatSession>) ?? [])
            .filter { !$0.archived }
            .sorted { ($0.lastMessageAt ?? $0.createdAt ?? .distantPast) > ($1.lastMessageAt ?? $1.createdAt ?? .distantPast) }
        if let latestChat = chatSessions.first, let chatId = latestChat.id {
            insertLayout(
                name: nil,
                tree: .leaf(WorkspacePane(kind: .chat, sessionId: chatId)),
                focusedPaneId: nil
            )
        }

        if let browserSessions = worktree.browserSessions, browserSessions.count > 0 {
            let sessionId = createBrowserWorkspaceSessionId(claimingLegacySessions: true)
            insertLayout(
                name: nil,
                tree: .leaf(WorkspacePane(kind: .browser, sessionId: sessionId)),
                focusedPaneId: nil
            )
        }

        if order == 0 {
            insertLayout(name: nil, tree: .leaf(WorkspacePane(kind: .empty)), focusedPaneId: nil)
        }

        saveContext()
    }
}
