import CoreData

extension ActiveTabIndicatorView {
    var tabState: WorktreeTabState {
        guard let worktreeId = worktree.id else {
            return WorktreeTabState()
        }
        return tabStateManager.getState(for: worktreeId)
    }

    var activeTabInfo: (icon: String, title: String)? {
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
                let title = terminalTitleRegistry.title(for: session) ?? "Terminal"
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

    func fetchChatSession(id: UUID) -> ChatSession? {
        let request = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    func fetchTerminalSession(id: UUID) -> TerminalSession? {
        let request = TerminalSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    func fetchBrowserSession(id: UUID) -> BrowserSession? {
        let request = BrowserSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
}
