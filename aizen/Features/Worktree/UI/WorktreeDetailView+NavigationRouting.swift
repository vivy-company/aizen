import ACP
import CoreData
import Foundation

extension WorktreeDetailView {
    func routeToChatSession(_ sessionId: UUID) {
        if activateLocalChatSession(sessionId) {
            return
        }

        postNavigateToChatSession(sessionId)
    }

    func activateLocalChatSession(_ sessionId: UUID) -> Bool {
        guard doesChatSessionBelongToCurrentWorktree(sessionId) else {
            return false
        }

        selectedTab = "chat"
        viewModel.selectedChatSessionId = sessionId
        return true
    }

    func postNavigateToChatSession(_ sessionId: UUID) {
        NotificationCenter.default.post(
            name: .navigateToChatSession,
            object: nil,
            userInfo: ["chatSessionId": sessionId]
        )
    }

    func doesChatSessionBelongToCurrentWorktree(_ sessionId: UUID) -> Bool {
        guard let worktreeId = worktree.id else { return false }
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND worktree.id == %@",
            sessionId as CVarArg,
            worktreeId as CVarArg
        )
        request.fetchLimit = 1
        return ((try? worktree.managedObjectContext?.fetch(request).first) != nil)
    }

    func containsTerminalSession(_ sessionId: UUID, worktreeId: UUID) -> Bool {
        let request: NSFetchRequest<TerminalSession> = TerminalSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, worktreeId as CVarArg)
        request.fetchLimit = 1
        return ((try? worktree.managedObjectContext?.fetch(request).first) != nil)
    }

    func containsBrowserSession(_ sessionId: UUID, worktreeId: UUID) -> Bool {
        let request: NSFetchRequest<BrowserSession> = BrowserSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, worktreeId as CVarArg)
        request.fetchLimit = 1
        return ((try? worktree.managedObjectContext?.fetch(request).first) != nil)
    }
}
