import ACP
import Foundation

extension WorktreeDetailView {
    func applyPendingNavigationDestinationIfNeeded() {
        guard let worktreeId = worktree.id,
              let destination = navigationSelectionStore.consumePendingWorktreeDestination(for: worktreeId) else {
            return
        }

        switch destination {
        case .tab(_, let tabId):
            if let kind = PaneKind(rawValue: tabId) {
                scene.workspace.revealKind(kind)
            }
        case .chatSession(_, let sessionId):
            _ = activateLocalChatSession(sessionId)
        case .terminalSession(_, let sessionId):
            if containsTerminalSession(sessionId) {
                scene.workspace.revealTerminalSession(sessionId)
            }
        case .browserSession(_, let sessionId):
            if containsBrowserSession(sessionId) {
                scene.workspace.revealKind(.browser)
                viewModel.selectedBrowserSessionId = sessionId
            }
        }
    }

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

        if let kind = PaneKind(rawValue: tabId) {
            scene.workspace.revealKind(kind)
        }
    }

    func handleSwitchToTerminalSession(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let sessionId = userInfo["sessionId"] as? UUID,
              targetWorktreeId == worktree.id else {
            return
        }

        if containsTerminalSession(sessionId) {
            scene.workspace.revealTerminalSession(sessionId)
        }
    }

    func handleSwitchToBrowserSession(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetWorktreeId = userInfo["worktreeId"] as? UUID,
              let sessionId = userInfo["sessionId"] as? UUID,
              targetWorktreeId == worktree.id else {
            return
        }

        if containsBrowserSession(sessionId) {
            scene.workspace.revealKind(.browser)
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
