//
//  MCPManagementStore+InstallActions.swift
//  aizen
//
//  Install, sync, and query helpers for Aizen-managed MCP servers.
//

import Foundation

extension MCPManagementStore {
    // MARK: - Install Package

    func installPackage(
        server: MCPServer,
        package: MCPPackage,
        agentId: String,
        env: [String: String]
    ) async throws {
        isInstalling = true
        defer { isInstalling = false }

        let serverName = extractServerName(from: server.name)

        let (command, args) = runtimeCommand(for: package)
        let serverDefinition = MCPServerDefinition.stdio(command: command, args: args, env: env)

        try await serverStore.saveDefaultServer(serverDefinition, named: serverName, agentId: agentId)
        await syncInstalled(agentId: agentId)
    }

    // MARK: - Install Remote

    func installRemote(
        server: MCPServer,
        remote: MCPRemote,
        agentId: String,
        env _: [String: String]
    ) async throws {
        isInstalling = true
        defer { isInstalling = false }

        let serverName = extractServerName(from: server.name)
        let headers = remote.headers?.compactMap { header -> MCPHeaderDefinition? in
            guard let value = header.value, !value.isEmpty else { return nil }
            return MCPHeaderDefinition(name: header.name, value: value)
        } ?? []

        let serverDefinition: MCPServerDefinition
        if remote.type == "sse" {
            serverDefinition = MCPServerDefinition.sse(url: remote.url, headers: headers)
        } else {
            serverDefinition = MCPServerDefinition.http(url: remote.url, headers: headers)
        }

        try await serverStore.saveDefaultServer(serverDefinition, named: serverName, agentId: agentId)
        await syncInstalled(agentId: agentId)
    }

    // MARK: - Remove

    func remove(serverName: String, agentId: String) async throws {
        isRemoving = true
        defer { isRemoving = false }

        try await serverStore.removeDefaultServer(named: serverName, agentId: agentId)
        await syncInstalled(agentId: agentId)
    }

    // MARK: - Sync

    func syncInstalled(agentId: String) async {
        isSyncing.insert(agentId)
        defer { isSyncing.remove(agentId) }

        let servers = await serverStore.defaultServers(for: agentId)
        let installed = servers.map { name, definition in
            MCPInstalledServer(
                serverName: name,
                displayName: name,
                agentId: agentId,
                packageType: definition.transport == .stdio ? "stdio" : nil,
                transportType: definition.transport.rawValue,
                configuredEnv: definition.env ?? [:],
                configuredHeaders: Dictionary(
                    uniqueKeysWithValues: (definition.headers ?? []).map { ($0.name, $0.value) }
                )
            )
        }

        installedServers[agentId] = installed
    }

    func isSyncingServers(for agentId: String) -> Bool {
        isSyncing.contains(agentId)
    }

    // MARK: - Query

    func isInstalled(serverName: String, agentId: String) -> Bool {
        let name = extractServerName(from: serverName)
        return installedServers[agentId]?.contains { $0.serverName.lowercased() == name.lowercased() } ?? false
    }

    func servers(for agentId: String) -> [MCPInstalledServer] {
        installedServers[agentId] ?? []
    }
}
