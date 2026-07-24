//
//  WorkspacePane.swift
//  aizen
//
//  A leaf in the workspace split tree: a typed content slot.
//

import Foundation

/// `id` is layout-level identity: it stays stable across tree mutations and kind
/// replacement, and is the key runtime resources (terminal surfaces, tmux sessions)
/// are bound to. `sessionId` binds the pane to its persisted session entity for
/// kinds that have one.
nonisolated struct WorkspacePane: Codable, Hashable, Identifiable {
    let id: String
    var kind: PaneKind
    var sessionId: UUID?

    init(id: String = UUID().uuidString, kind: PaneKind, sessionId: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.sessionId = sessionId
    }
}
