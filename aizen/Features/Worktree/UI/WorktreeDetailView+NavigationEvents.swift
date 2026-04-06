import ACP
import CoreData
import Foundation

extension WorktreeDetailView {
    func navigateToChatSession(_ sessionId: UUID) {
        if activateLocalChatSession(sessionId) {
            return
        }

        postNavigateToChatSession(sessionId)
    }

    func handleSwitchToChatSession(_ notification: Notification) {
        guard let sessionId = notification.userInfo?["chatSessionId"] as? UUID else {
            return
        }
        _ = activateLocalChatSession(sessionId)
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

        if containsTerminalSession(sessionId, worktreeId: targetWorktreeId) {
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

        if containsBrowserSession(sessionId, worktreeId: targetWorktreeId) {
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

        routeToChatSession(sessionId)
    }

    func handleSwitchToChat(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? UUID else {
            return
        }

        routeToChatSession(sessionId)
    }
}
