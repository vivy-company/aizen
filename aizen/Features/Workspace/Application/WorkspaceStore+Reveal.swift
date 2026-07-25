//
//  WorkspaceStore+Reveal.swift
//  aizen
//
//  Navigation entry points: bring a session or pane kind on screen,
//  creating a layout for it when none hosts it yet.
//

import Foundation

@MainActor
extension WorkspaceStore {
    /// Focuses the pane bound to the chat session, selecting or creating a
    /// layout as needed. Returns false when the session doesn't belong here.
    @discardableResult
    func revealChatSession(_ sessionId: UUID) -> Bool {
        guard let session = chatSession(withId: sessionId) else { return false }
        if session.archived {
            session.archived = false
            saveContext()
        }
        revealPane(matching: { $0.kind == .chat && $0.sessionId == sessionId }) {
            .leaf(WorkspacePane(kind: .chat, sessionId: sessionId))
        }
        return true
    }

    func revealTerminalSession(_ sessionId: UUID) {
        guard terminalSession(withId: sessionId) != nil else { return }
        revealPane(matching: { $0.kind == .terminal && $0.sessionId == sessionId }) {
            .leaf(WorkspacePane(kind: .terminal, sessionId: sessionId))
        }
    }

    /// Focuses the browser pane that owns the requested browser tab.
    /// Browser tab identifiers are scoped by the pane's workspace session.
    @discardableResult
    func revealBrowserSession(_ sessionId: UUID) -> Bool {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        guard let workspaceSessionId = sessions.first(where: { $0.id == sessionId })?.workspaceSessionId else {
            return false
        }

        revealPane(matching: {
            $0.kind == .browser && $0.sessionId == workspaceSessionId
        }) {
            .leaf(WorkspacePane(kind: .browser, sessionId: workspaceSessionId))
        }
        return true
    }

    /// Focuses any pane of the given kind, or creates a layout hosting one.
    func revealKind(_ kind: PaneKind) {
        revealPane(matching: { $0.kind == kind }) { [weak self] in
            guard let self else { return .leaf(WorkspacePane(kind: kind)) }
            return .leaf(self.makePane(kind: kind, inheritingFrom: nil))
        }
    }

    private func revealPane(
        matching predicate: (WorkspacePane) -> Bool,
        makeTree: () -> WorkspaceSplitNode
    ) {
        if let pane = tree.allPanes().first(where: predicate) {
            focusPane(pane.id)
            return
        }

        for layout in layouts where layout.id != activeLayoutId {
            guard let layoutTree = layout.treeJSON.flatMap(WorkspaceLayoutCodec.decode) else { continue }
            if let pane = layoutTree.allPanes().first(where: predicate) {
                selectLayout(layout)
                focusPane(pane.id)
                return
            }
        }

        addLayout(tree: makeTree())
    }
}
