//
//  ChatSessionPersistence+LegacyRecovery.swift
//  aizen
//
//  Legacy detached-session recovery compatibility path.
//

import CoreData
import Foundation
import os

extension ChatSessionPersistence {
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
