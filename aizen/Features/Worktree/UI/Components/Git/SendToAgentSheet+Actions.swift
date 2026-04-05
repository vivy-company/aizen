//
//  SendToAgentSheet+Actions.swift
//  aizen
//

import SwiftUI

extension SendToAgentSheet {
    func sendToAgent() {
        guard let option = selectedOption else { return }

        switch option {
        case .existingChat(let sessionId):
            sendToExistingChat(sessionId: sessionId)
        case .newChat(let agentId):
            createNewChatAndSend(agentId: agentId)
        }

        onDismiss()
        onSend()
    }

    func sendToExistingChat(sessionId: UUID) {
        ChatSessionRegistry.shared.setPendingAttachments([attachment], for: sessionId)

        NotificationCenter.default.post(
            name: .switchToChat,
            object: nil,
            userInfo: ["sessionId": sessionId]
        )
    }

    func createNewChatAndSend(agentId: String) {
        guard let worktree = worktree,
              let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let displayName = AgentRegistry.shared.getMetadata(for: agentId)?.name ?? agentId.capitalized
        session.title = displayName
        session.agentName = agentId
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()

            NotificationCenter.default.post(
                name: .sendMessageToChat,
                object: nil,
                userInfo: [
                    "sessionId": session.id as Any,
                    "attachment": attachment
                ]
            )
        } catch {
            print("Failed to create chat session: \(error)")
        }
    }
}
