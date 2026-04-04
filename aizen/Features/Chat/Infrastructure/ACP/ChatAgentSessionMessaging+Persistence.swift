//
//  ChatAgentSessionMessaging+Persistence.swift
//  aizen
//

import ACP
import CoreData
import Foundation

@MainActor
extension ChatAgentSession {
    func updateChatSessionMetadata(chatSessionId: UUID) async throws {
        let bgContext = PersistenceController.shared.container.newBackgroundContext()

        try await bgContext.perform {
            let fetchRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let session = try bgContext.fetch(fetchRequest).first else {
                throw ChatSessionPersistenceError.chatSessionNotFound(chatSessionId)
            }

            session.messageCount += 1
            session.lastMessageAt = Date()

            try bgContext.save()
        }
    }

    func persistMessage(
        id: UUID,
        role: String,
        content: String,
        contentBlocks: [ContentBlock],
        chatSessionId: UUID,
        toolCalls: [ToolCall] = []
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let agentName = self.agentName

        try await context.perform {
            let fetchRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatSession = try context.fetch(fetchRequest).first else {
                throw NSError(
                    domain: "ChatAgentSession",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "ChatSession not found"]
                )
            }

            let chatMessage = ChatMessage(context: context)
            chatMessage.id = id
            chatMessage.role = role
            chatMessage.timestamp = Date()
            chatMessage.agentName = agentName

            let encoder = JSONEncoder()
            if let contentJSON = try? encoder.encode(contentBlocks),
               let jsonString = String(data: contentJSON, encoding: .utf8) {
                chatMessage.contentJSON = jsonString
            } else {
                chatMessage.contentJSON = content
            }

            chatMessage.session = chatSession

            if !toolCalls.isEmpty {
                for call in toolCalls {
                    let record = ToolCallRecord(context: context)
                    record.id = call.toolCallId
                    record.title = call.title
                    record.kind = call.kind?.rawValue ?? ToolKind.other.rawValue
                    record.status = call.status.rawValue
                    record.timestamp = call.timestamp
                    if let encoded = try? encoder.encode(call),
                       let jsonString = String(data: encoded, encoding: .utf8) {
                        record.contentJSON = jsonString
                    } else if let encoded = try? encoder.encode(call.content),
                              let jsonString = String(data: encoded, encoding: .utf8) {
                        record.contentJSON = jsonString
                    } else {
                        record.contentJSON = ""
                    }
                    record.message = chatMessage
                }
            }

            try context.save()
        }
    }
}
