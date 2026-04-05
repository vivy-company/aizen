//
//  ChatSessionPersistence+SessionIDs.swift
//  aizen
//
//  ACP session ID persistence helpers.
//

import CoreData
import Foundation
import os

extension ChatSessionPersistence {
    // MARK: - Session ID Persistence

    func saveSessionId(_ acpSessionId: String, for chatSessionId: UUID, in context: NSManagedObjectContext) async throws {
        try await modifySession(chatSessionId, in: context) { chatSession in
            chatSession.acpSessionId = acpSessionId
            self.logger.info("Saved ACP session ID for ChatSession \(chatSessionId.uuidString)")
        }
    }

    func clearSessionId(for chatSessionId: UUID, in context: NSManagedObjectContext) async throws {
        try await modifySession(chatSessionId, in: context) { chatSession in
            chatSession.acpSessionId = nil
            self.logger.info("Cleared ACP session ID for ChatSession \(chatSessionId.uuidString)")
        }
    }

    func getSessionId(for chatSessionId: UUID, in context: NSManagedObjectContext) async -> String? {
        await context.perform {
            let fetchRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatSession = try? context.fetch(fetchRequest).first else {
                self.logger.warning("ChatSession \(chatSessionId.uuidString) not found")
                return nil
            }

            return chatSession.acpSessionId
        }
    }
}
