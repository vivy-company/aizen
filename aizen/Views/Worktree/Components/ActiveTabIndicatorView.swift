//
//  ActiveTabIndicatorView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 19.11.25.
//

import ACP
import SwiftUI

struct ActiveTabIndicatorView: View {
    let worktree: Worktree
    @ObservedObject var tabStateManager: WorktreeTabStateManager
    @Environment(\.managedObjectContext) private var viewContext

    private var tabState: WorktreeTabState {
        guard let worktreeId = worktree.id else {
            return WorktreeTabState()
        }
        return tabStateManager.getState(for: worktreeId)
    }

    private var activeTabInfo: (icon: String, title: String)? {
        guard worktree.id != nil else { return nil }

        let viewType = tabState.viewType

        switch viewType {
        case "chat":
            if let sessionId = tabState.chatSessionId,
               let session = fetchChatSession(id: sessionId) {
                let title = session.title ?? session.agentName?.capitalized ?? "Chat"
                return ("message", title)
            }
            return ("message", "Chat")

        case "terminal":
            if let sessionId = tabState.terminalSessionId,
               let session = fetchTerminalSession(id: sessionId) {
                let title = session.title ?? "Terminal"
                return ("terminal", title)
            }
            return ("terminal", "Terminal")

        case "browser":
            if let sessionId = tabState.browserSessionId,
               let session = fetchBrowserSession(id: sessionId) {
                let title = session.title ?? session.url ?? "Browser"
                return ("globe", title)
            }
            return ("globe", "Browser")

        case "files":
            return ("folder", "Files")

        default:
            return nil
        }
    }

    var body: some View {
        if let info = activeTabInfo {
            HStack(spacing: 4) {
                Image(systemName: info.icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(info.title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Core Data Queries

    private func fetchChatSession(id: UUID) -> ChatSession? {
        let request = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    private func fetchTerminalSession(id: UUID) -> TerminalSession? {
        let request = TerminalSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    private func fetchBrowserSession(id: UUID) -> BrowserSession? {
        let request = BrowserSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
}
