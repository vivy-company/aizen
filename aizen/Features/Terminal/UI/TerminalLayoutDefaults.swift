//
//  TerminalLayoutDefaults.swift
//  aizen
//
//  Seeding defaults for terminal session split layouts.
//

import Foundation

enum TerminalLayoutDefaults {
    static func paneId(sessionId: UUID?, focusedPaneId: String?) -> String {
        if let focusedPaneId {
            let trimmed = focusedPaneId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let sessionId {
            return sessionId.uuidString
        }

        return UUID().uuidString
    }

    static func defaultLayout(paneId: String) -> WorkspaceSplitNode {
        .leaf(WorkspacePane(id: paneId, kind: .terminal))
    }
}
