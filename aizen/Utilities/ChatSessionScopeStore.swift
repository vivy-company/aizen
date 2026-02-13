//
//  ChatSessionScopeStore.swift
//  aizen
//
//  Persists last-known session scope for detached (closed) chat sessions.
//

import Foundation

@MainActor
final class ChatSessionScopeStore {
    static let shared = ChatSessionScopeStore()

    struct Snapshot: Sendable {
        let worktreeBySessionId: [UUID: UUID]
        let workspaceBySessionId: [UUID: UUID]

        func worktreeId(for sessionId: UUID) -> UUID? {
            worktreeBySessionId[sessionId]
        }

        func workspaceId(for sessionId: UUID) -> UUID? {
            workspaceBySessionId[sessionId]
        }
    }

    private let worktreeMapKey = "chatSession.lastWorktreeBySessionId"
    private let workspaceMapKey = "chatSession.lastWorkspaceBySessionId"
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setScope(sessionId: UUID, worktreeId: UUID?, workspaceId: UUID?) {
        let key = sessionId.uuidString

        var worktreeMap = decodeMap(forKey: worktreeMapKey)
        if let worktreeId {
            worktreeMap[key] = worktreeId.uuidString
        } else {
            worktreeMap.removeValue(forKey: key)
        }
        defaults.set(worktreeMap, forKey: worktreeMapKey)

        var workspaceMap = decodeMap(forKey: workspaceMapKey)
        if let workspaceId {
            workspaceMap[key] = workspaceId.uuidString
        } else {
            workspaceMap.removeValue(forKey: key)
        }
        defaults.set(workspaceMap, forKey: workspaceMapKey)
    }

    func clearScope(sessionId: UUID) {
        setScope(sessionId: sessionId, worktreeId: nil, workspaceId: nil)
    }

    func worktreeId(for sessionId: UUID) -> UUID? {
        let map = decodeMap(forKey: worktreeMapKey)
        guard let raw = map[sessionId.uuidString] else { return nil }
        return UUID(uuidString: raw)
    }

    func workspaceId(for sessionId: UUID) -> UUID? {
        let map = decodeMap(forKey: workspaceMapKey)
        guard let raw = map[sessionId.uuidString] else { return nil }
        return UUID(uuidString: raw)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            worktreeBySessionId: decodeUUIDMap(forKey: worktreeMapKey),
            workspaceBySessionId: decodeUUIDMap(forKey: workspaceMapKey)
        )
    }

    private func decodeMap(forKey key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func decodeUUIDMap(forKey key: String) -> [UUID: UUID] {
        decodeMap(forKey: key).reduce(into: [UUID: UUID]()) { partialResult, item in
            guard let sessionId = UUID(uuidString: item.key),
                  let scopeId = UUID(uuidString: item.value) else {
                return
            }
            partialResult[sessionId] = scopeId
        }
    }
}
