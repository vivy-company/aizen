//
//  SessionPersistenceService.swift
//  aizen
//
//  Service for persisting ACP session IDs to Core Data
//  Single Responsibility: Bridging between AgentSession (runtime) and ChatSession (persistence)
//

import ACP
import Foundation
import CoreData
import os.log

/// Errors related to session persistence operations
enum SessionPersistenceError: LocalizedError {
    case chatSessionNotFound(UUID)
    case contextNotAvailable
    case saveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .chatSessionNotFound(let id):
            return "Chat session with ID \(id) not found in Core Data"
        case .contextNotAvailable:
            return "Core Data context not available"
        case .saveFailed(let error):
            return "Failed to save session data: \(error.localizedDescription)"
        }
    }
}

/// Service responsible for persisting ACP session state to Core Data
final class SessionPersistenceService {
    static let shared = SessionPersistenceService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "SessionPersistence")
    private static let legacyWorktreeMapKey = "chatSession.lastWorktreeBySessionId"
    private static let legacyWorkspaceMapKey = "chatSession.lastWorkspaceBySessionId"
    private static let legacyRecoveryCompletedKey = "chatSession.legacyDetachedRecovery.completed.v2"
    private static let legacyDefaultsDomains = [
        "win.aizen.app",
        "wiedymi.com.aizen",
        "com.aizen.app",
        "aizen"
    ]
    
    private init() {}
    
    // MARK: - Private Helpers
    
    private func modifySession(
        _ sessionId: UUID,
        in context: NSManagedObjectContext,
        modifier: @escaping (ChatSession) throws -> Void
    ) async throws {
        try await context.perform {
            let fetchRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
            fetchRequest.fetchLimit = 1
            
            guard let chatSession = try context.fetch(fetchRequest).first else {
                throw SessionPersistenceError.chatSessionNotFound(sessionId)
            }
            
            try modifier(chatSession)
            
            do {
                try context.save()
            } catch {
                throw SessionPersistenceError.saveFailed(error)
            }
        }
    }
    
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
    
    // MARK: - Message Count Updates
    
    func updateMessageCount(_ count: Int32, for chatSessionId: UUID, in context: NSManagedObjectContext) async throws {
        try await modifySession(chatSessionId, in: context) { chatSession in
            chatSession.messageCount = count
        }
    }
    
    func incrementMessageCount(for chatSessionId: UUID, in context: NSManagedObjectContext) async throws {
        try await modifySession(chatSessionId, in: context) { chatSession in
            chatSession.messageCount += 1
            chatSession.lastMessageAt = Date()
        }
    }
    
    // MARK: - Archive State
    
    func archiveSession(_ chatSessionId: UUID, in context: NSManagedObjectContext) async throws {
        try await modifySession(chatSessionId, in: context) { chatSession in
            chatSession.archived = true
            self.logger.info("Archived ChatSession \(chatSessionId.uuidString)")
        }
    }
    
    func unarchiveSession(_ chatSessionId: UUID, in context: NSManagedObjectContext) async throws {
        try await modifySession(chatSessionId, in: context) { chatSession in
            chatSession.archived = false
            self.logger.info("Unarchived ChatSession \(chatSessionId.uuidString)")
        }
    }
    
    func backfillSessionMetadata(in context: NSManagedObjectContext) async {
        await context.perform {
            let fetchRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "messageCount == 0 OR lastMessageAt == nil")
            
            do {
                let sessions = try context.fetch(fetchRequest)
                var backfilledCount = 0
                
                for session in sessions {
                    let messages = (session.messages as? Set<ChatMessage>) ?? []
                    
                    if session.messageCount == 0 {
                        session.messageCount = Int32(messages.count)
                    }
                    
                    if session.lastMessageAt == nil, let latestMessage = messages.max(by: { $0.timestamp ?? Date.distantPast < $1.timestamp ?? Date.distantPast }) {
                        session.lastMessageAt = latestMessage.timestamp
                    }
                    
                    if !messages.isEmpty {
                        backfilledCount += 1
                    }
                }
                
                if backfilledCount > 0 {
                    try context.save()
                    self.logger.info("Backfilled metadata for \(backfilledCount) chat sessions")
                }
            } catch {
                self.logger.error("Failed to backfill session metadata: \(error.localizedDescription)")
            }
        }
    }

    /// Compatibility migration:
    /// Reattach legacy detached sessions (worktree == nil) using the previously persisted
    /// session->worktree map from older builds, and archive them so they remain resumable
    /// without appearing as open tabs.
    func recoverDetachedSessionsFromLegacyScope(in context: NSManagedObjectContext) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.legacyRecoveryCompletedKey) else {
            return
        }

        func decodeStringMap(_ raw: Any?) -> [String: String] {
            if let map = raw as? [String: String] {
                return map
            }
            if let map = raw as? [String: Any] {
                var result: [String: String] = [:]
                for (key, value) in map {
                    if let stringValue = value as? String {
                        result[key] = stringValue
                    }
                }
                return result
            }
            return [:]
        }

        func clearLegacyKeysAndMarkCompleted(sourceDomains: Set<String>) {
            defaults.set(true, forKey: Self.legacyRecoveryCompletedKey)
            defaults.removeObject(forKey: Self.legacyWorktreeMapKey)
            defaults.removeObject(forKey: Self.legacyWorkspaceMapKey)

            for domain in sourceDomains {
                guard var domainValues = defaults.persistentDomain(forName: domain) else { continue }
                domainValues.removeValue(forKey: Self.legacyWorktreeMapKey)
                domainValues.removeValue(forKey: Self.legacyWorkspaceMapKey)
                domainValues[Self.legacyRecoveryCompletedKey] = true
                defaults.setPersistentDomain(domainValues, forName: domain)
            }
        }

        var sourceDomains = Set<String>()
        var rawMap = decodeStringMap(defaults.object(forKey: Self.legacyWorktreeMapKey))

        if rawMap.isEmpty {
            for domain in Self.legacyDefaultsDomains {
                guard let values = defaults.persistentDomain(forName: domain) else { continue }
                let map = decodeStringMap(values[Self.legacyWorktreeMapKey])
                if !map.isEmpty {
                    rawMap = map
                    sourceDomains.insert(domain)
                    break
                }
            }
        }

        let scopeMap = rawMap.reduce(into: [UUID: UUID]()) { partialResult, item in
            guard let sessionId = UUID(uuidString: item.key),
                  let worktreeId = UUID(uuidString: item.value) else {
                return
            }
            partialResult[sessionId] = worktreeId
        }

        guard !scopeMap.isEmpty else {
            clearLegacyKeysAndMarkCompleted(sourceDomains: sourceDomains)
            return
        }

        enum RecoveryResult {
            case success(Int)
            case noDetachedSessions
            case failed(String)
        }

        let result: RecoveryResult = await context.perform {
            let detachedRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            detachedRequest.predicate = NSPredicate(format: "worktree == nil")

            do {
                let detachedSessions = try context.fetch(detachedRequest)
                guard !detachedSessions.isEmpty else {
                    return .noDetachedSessions
                }

                let targetWorktreeIds = Set(scopeMap.values)
                guard !targetWorktreeIds.isEmpty else {
                    return .success(0)
                }

                let worktreeRequest: NSFetchRequest<Worktree> = Worktree.fetchRequest()
                worktreeRequest.predicate = NSPredicate(format: "id IN %@", Array(targetWorktreeIds))
                let worktrees = try context.fetch(worktreeRequest)
                let worktreeById: [UUID: Worktree] = Dictionary(
                    uniqueKeysWithValues: worktrees.compactMap { worktree in
                        guard let id = worktree.id else { return nil }
                        return (id, worktree)
                    }
                )

                var recovered = 0
                for session in detachedSessions {
                    guard let sessionId = session.id,
                          let mappedWorktreeId = scopeMap[sessionId],
                          let worktree = worktreeById[mappedWorktreeId],
                          !worktree.isDeleted else {
                        continue
                    }

                    session.worktree = worktree
                    session.archived = true
                    recovered += 1
                }

                if recovered > 0 {
                    try context.save()
                }
                return .success(recovered)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        switch result {
        case .success(let recovered):
            if recovered > 0 {
                logger.info("Recovered \(recovered) legacy detached chat sessions")
            } else {
                logger.info("No legacy detached chat sessions were recoverable")
            }
            clearLegacyKeysAndMarkCompleted(sourceDomains: sourceDomains)
        case .noDetachedSessions:
            clearLegacyKeysAndMarkCompleted(sourceDomains: sourceDomains)
        case .failed(let message):
            logger.error("Failed to recover detached chat sessions: \(message)")
        }
    }
}
