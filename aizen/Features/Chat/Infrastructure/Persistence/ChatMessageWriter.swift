//
//  ChatMessageWriter.swift
//  aizen
//

import ACP
import CoreData
import Foundation

struct PersistedChatMessagePayload {
    let id: UUID
    let role: String
    let content: String
    let contentBlocks: [ContentBlock]
    let chatSessionId: UUID
    let agentName: String
    let toolCalls: [ToolCall]
}

final class ChatMessageWriter {
    static let shared = ChatMessageWriter(container: PersistenceController.shared.container)

    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func persistMessage(_ payload: PersistedChatMessagePayload) async throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let persistedAt = Date()

        try await context.perform {
            let sessionRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            sessionRequest.predicate = NSPredicate(format: "id == %@", payload.chatSessionId as CVarArg)
            sessionRequest.fetchLimit = 1

            guard let chatSession = try context.fetch(sessionRequest).first else {
                throw ChatSessionPersistenceError.chatSessionNotFound(payload.chatSessionId)
            }

            let messageRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
            messageRequest.predicate = NSPredicate(format: "id == %@", payload.id as CVarArg)
            messageRequest.fetchLimit = 1

            let existingMessage = try context.fetch(messageRequest).first
            let chatMessage = existingMessage ?? ChatMessage(context: context)
            let isNewMessage = existingMessage == nil

            chatMessage.id = payload.id
            chatMessage.role = payload.role
            chatMessage.timestamp = persistedAt
            chatMessage.agentName = payload.agentName
            chatMessage.contentJSON = Self.encodeContentJSON(
                content: payload.content,
                contentBlocks: payload.contentBlocks
            )
            chatMessage.session = chatSession

            if !payload.toolCalls.isEmpty {
                let existingRecords = ((chatMessage.toolCalls as? Set<ToolCallRecord>) ?? []).reduce(into: [String: ToolCallRecord]()) { partialResult, record in
                    guard let id = record.id else { return }
                    partialResult[id] = record
                }

                for call in payload.toolCalls {
                    let record = existingRecords[call.toolCallId] ?? ToolCallRecord(context: context)
                    record.id = call.toolCallId
                    record.title = call.title
                    record.kind = call.kind?.rawValue ?? ToolKind.other.rawValue
                    record.status = call.status.rawValue
                    record.timestamp = call.timestamp
                    record.contentJSON = Self.encodeToolCallJSON(call)
                    record.message = chatMessage
                }
            }

            if isNewMessage {
                chatSession.messageCount += 1
            }
            chatSession.lastMessageAt = persistedAt

            if context.hasChanges {
                try context.save()
            }
        }
    }

    private static func encodeContentJSON(content: String, contentBlocks: [ContentBlock]) -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(contentBlocks),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return content
    }

    private static func encodeToolCallJSON(_ call: ToolCall) -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(call),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        if let data = try? encoder.encode(call.content),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return ""
    }
}
