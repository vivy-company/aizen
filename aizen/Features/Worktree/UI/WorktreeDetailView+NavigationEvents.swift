import ACP
import CoreData
import Foundation

extension WorktreeDetailView {
    func navigateToChatSession(_ sessionId: UUID) {
        guard let worktreeId = worktree.id else { return }
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, worktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        } else {
            NotificationCenter.default.post(
                name: .navigateToChatSession,
                object: nil,
                userInfo: ["chatSessionId": sessionId]
            )
        }
    }

    func handleSwitchToChatSession(_ notification: Notification) {
        guard let sessionId = notification.userInfo?["chatSessionId"] as? UUID else {
            return
        }
        guard let worktreeId = worktree.id else { return }
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, worktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        }
    }

    func handleSwitchToWorktreeTab(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let tabId = userInfo["tabId"] as? String,
              targetWorktreeId == worktree.id else {
            return
        }

        guard visibleTabIds.contains(tabId) else { return }
        selectedTab = tabId
    }

    func handleSwitchToTerminalSession(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let sessionId = userInfo["sessionId"] as? UUID,
              targetWorktreeId == worktree.id else {
            return
        }

        let request: NSFetchRequest<TerminalSession> = TerminalSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, targetWorktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "terminal"
            viewModel.selectedTerminalSessionId = sessionId
        }
    }

    func handleSwitchToBrowserSession(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let sessionId = userInfo["sessionId"] as? UUID,
              targetWorktreeId == worktree.id else {
            return
        }

        let request: NSFetchRequest<BrowserSession> = BrowserSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND worktree.id == %@", sessionId as CVarArg, targetWorktreeId as CVarArg)
        request.fetchLimit = 1

        if let _ = try? worktree.managedObjectContext?.fetch(request).first {
            selectedTab = "browser"
            viewModel.selectedBrowserSessionId = sessionId
        }
    }

    func handleSendMessageToChat(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? UUID else {
            return
        }

        let attachment: ChatAttachment
        if let existingAttachment = userInfo["attachment"] as? ChatAttachment {
            attachment = existingAttachment
        } else if let message = userInfo["message"] as? String {
            attachment = .reviewComments(message)
        } else {
            return
        }

        ChatSessionRegistry.shared.setPendingAttachments([attachment], for: sessionId)

        if doesChatSessionBelongToCurrentWorktree(sessionId) {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        } else {
            NotificationCenter.default.post(
                name: .navigateToChatSession,
                object: nil,
                userInfo: ["chatSessionId": sessionId]
            )
        }
    }

    func handleSwitchToChat(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? UUID else {
            return
        }

        if doesChatSessionBelongToCurrentWorktree(sessionId) {
            selectedTab = "chat"
            viewModel.selectedChatSessionId = sessionId
        } else {
            NotificationCenter.default.post(
                name: .navigateToChatSession,
                object: nil,
                userInfo: ["chatSessionId": sessionId]
            )
        }
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
}
