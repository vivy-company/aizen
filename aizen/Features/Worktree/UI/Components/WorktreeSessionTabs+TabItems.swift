//
//  WorktreeSessionTabs+TabItems.swift
//  aizen
//
//  Session tab item views
//

import SwiftUI

struct ChatSessionTabItemView: View {
    let session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @ObservedObject private var sessionManager = ChatSessionRegistry.shared

    var body: some View {
        let hasPendingPermission = session.id.map { sessionManager.hasPendingPermission(for: $0) } ?? false

        SessionTabButton(isSelected: isSelected, action: onSelect) {
            HStack(spacing: 6) {
                DetailCloseButton(action: onClose, size: 10)

                AgentIconView(agent: session.agentName ?? AgentRegistry.defaultAgentID, size: 14)

                Text(session.title ?? session.agentName?.capitalized ?? String(localized: "worktree.session.chat"))
                    .font(.callout)

                if hasPendingPermission {
                    PendingPermissionIndicator()
                }
            }
        }
    }
}

struct TerminalSessionTabItemView: View {
    let session: TerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @ObservedObject private var terminalTitleRegistry = TerminalTitleRegistry.shared

    var body: some View {
        SessionTabButton(isSelected: isSelected, action: onSelect) {
            HStack(spacing: 6) {
                DetailCloseButton(action: onClose, size: 10)

                Image(systemName: "terminal")
                    .font(.system(size: 12))

                Text(terminalTitleRegistry.title(for: session) ?? String(localized: "worktree.session.terminal"))
                    .font(.callout)

                TerminalPersistenceIndicator()
            }
        }
    }
}
