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
        viewModel.containsChatSession(sessionId)
    }

    func containsTerminalSession(_ sessionId: UUID) -> Bool {
        viewModel.containsTerminalSession(sessionId)
    }

    func containsBrowserSession(_ sessionId: UUID) -> Bool {
        viewModel.containsBrowserSession(sessionId)
    }
}
