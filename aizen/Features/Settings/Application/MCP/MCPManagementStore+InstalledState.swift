//
//  MCPManagementStore+InstalledState.swift
//  aizen
//
//  Installed-state sync and query helpers for Aizen-managed MCP servers.
//

import Foundation

extension MCPManagementStore {
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
