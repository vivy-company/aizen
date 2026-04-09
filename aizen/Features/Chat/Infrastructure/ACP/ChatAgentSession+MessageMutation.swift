//
//  ChatAgentSession+MessageMutation.swift
//  aizen
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    func addUserMessage(_ content: String, contentBlocks: [ContentBlock] = []) {
        let messageId = UUID()
        messages.append(
            MessageItem(
                id: messageId.uuidString,
                role: .user,
                content: content,
                timestamp: Date(),
                contentBlocks: contentBlocks
            ))
        trimMessagesIfNeeded()

        if let chatSessionId = chatSessionId {
            Task {
                do {
                    try await self.persistMessage(
                        id: messageId,
                        role: "user",
                        content: content,
                        contentBlocks: contentBlocks,
                        chatSessionId: chatSessionId
                    )
                } catch {
                }
            }
        }
    }

    func markLastMessageComplete() {
        flushAgentMessageBuffer()
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            let completedMessage = messages[lastIndex]
            let completionTimestamp = Date()
            let executionTime = completedMessage.startTime.map { completionTimestamp.timeIntervalSince($0) }
            let updatedMessage = MessageItem(
                id: completedMessage.id,
                role: completedMessage.role,
                content: completedMessage.content,
                timestamp: completedMessage.timestamp,
                toolCalls: completedMessage.toolCalls,
                contentBlocks: completedMessage.contentBlocks,
                isComplete: true,
                startTime: completedMessage.startTime,
                executionTime: executionTime,
                requestId: completedMessage.requestId
            )
            var updatedMessages = messages
            updatedMessages[lastIndex] = updatedMessage
            messages = updatedMessages

            if let chatSessionId = chatSessionId,
               let messageId = UUID(uuidString: completedMessage.id) {
                let toolCallsToPersist = toolCalls.filter {
                    !persistedToolCallIds.contains($0.toolCallId) && $0.timestamp <= completionTimestamp
                }
                Task {
                    do {
                        try await self.persistMessage(
                            id: messageId,
                            role: "agent",
                            content: completedMessage.content,
                            contentBlocks: completedMessage.contentBlocks,
                            chatSessionId: chatSessionId,
                            toolCalls: toolCallsToPersist
                        )
                        self.persistedToolCallIds.formUnion(toolCallsToPersist.map { $0.toolCallId })
                    } catch {
                    }
                }
            }
        }
    }

    func addAgentMessage(
        _ content: String,
        toolCalls: [ToolCall] = [],
        contentBlocks: [ContentBlock] = [],
        isComplete: Bool = true,
        startTime: Date? = nil,
        requestId: String? = nil
    ) {
        let messageId = UUID()
        let newMessage = MessageItem(
            id: messageId.uuidString,
            role: .agent,
            content: content,
            timestamp: Date(),
            toolCalls: toolCalls,
            contentBlocks: contentBlocks,
            isComplete: isComplete,
            startTime: startTime,
            executionTime: nil,
            requestId: requestId
        )
        messages.append(newMessage)
        trimMessagesIfNeeded()
    }

    func addSystemMessage(_ content: String) {
        messages.append(
            MessageItem(
                id: UUID().uuidString,
                role: .system,
                content: content,
                timestamp: Date()
            ))
        trimMessagesIfNeeded()
    }

    func trimMessagesIfNeeded() {
        let excess = messages.count - Self.maxMessageCount
        guard excess > 0 else { return }
        messages.removeFirst(excess)
    }
}
