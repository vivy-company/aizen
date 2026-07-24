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
        case .files, .browser, .gitDiff, .empty:
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
            return WorkspacePane(id: id, kind: .chat, sessionId: createChatSession()?.id)

        case .files, .browser, .gitDiff, .empty:
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

    private func createChatSession() -> ChatSession? {
        let session = ChatSession(context: viewContext)
        session.id = UUID()
        let agent = defaultAgentId()
        session.agentName = agent
        session.title = AgentRegistry.shared.getMetadata(for: agent)?.name ?? agent.capitalized
        session.archived = false
        session.createdAt = Date()
        session.worktree = worktree
        saveContext()
        return session
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

        case .files, .browser, .gitDiff, .empty:
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
            insertLayout(name: nil, tree: .leaf(WorkspacePane(kind: .browser)), focusedPaneId: nil)
        }

        if order == 0 {
            insertLayout(name: nil, tree: .leaf(WorkspacePane(kind: .empty)), focusedPaneId: nil)
        }

        saveContext()
    }
}
