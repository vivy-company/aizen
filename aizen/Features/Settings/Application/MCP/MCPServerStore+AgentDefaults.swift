import Foundation

extension MCPServerStore {
    // MARK: - Agent Defaults

    func defaultServers(for agentId: String) -> [String: MCPServerDefinition] {
        let snapshot = loadSnapshot()
        return snapshot.agentDefaults[agentId] ?? [:]
    }

    func saveDefaultServer(_ server: MCPServerDefinition, named name: String, agentId: String) throws {
        var snapshot = loadSnapshot()
        var servers = snapshot.agentDefaults[agentId] ?? [:]
        servers[name] = server
        snapshot.agentDefaults[agentId] = servers
        try saveSnapshot(snapshot)
    }

    func removeDefaultServer(named name: String, agentId: String) throws {
        var snapshot = loadSnapshot()
        var servers = snapshot.agentDefaults[agentId] ?? [:]
        servers.removeValue(forKey: name)
        snapshot.agentDefaults[agentId] = servers
        try saveSnapshot(snapshot)
    }
}
