//
//  ChatAgentSessionMessaging+Persistence.swift
//  aizen
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    func persistMessage(
        id: UUID,
        role: String,
        content: String,
        contentBlocks: [ContentBlock],
        chatSessionId: UUID,
        toolCalls: [ToolCall] = []
    ) async throws {
        let payload = PersistedChatMessagePayload(
            id: id,
            role: role,
            content: content,
            contentBlocks: contentBlocks,
            chatSessionId: chatSessionId,
            agentName: agentName,
            toolCalls: toolCalls
        )
        try await ChatMessageWriter.shared.persistMessage(payload)
    }
}
