import Foundation

extension MCPServerStore {
    // MARK: - Session Overrides

    func servers(for agentId: String, sessionId: UUID?) -> [String: MCPServerDefinition] {
        var merged = defaultServers(for: agentId)
        guard let sessionId else { return merged }

        let snapshot = loadSnapshot()
        let overrides = snapshot.sessionOverrides[sessionId.uuidString] ?? [String: MCPServerDefinition]()
        for (name, entry) in overrides {
            merged[name] = entry
        }
        return merged
    }

    func replaceSessionServers(_ servers: [String: MCPServerDefinition], sessionId: UUID) throws {
        var snapshot = loadSnapshot()
        snapshot.sessionOverrides[sessionId.uuidString] = servers
        try saveSnapshot(snapshot)
    }

    func clearSessionServers(sessionId: UUID) throws {
        var snapshot = loadSnapshot()
        snapshot.sessionOverrides.removeValue(forKey: sessionId.uuidString)
        try saveSnapshot(snapshot)
    }
}
