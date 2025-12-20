//
//  MCPManager.swift
//  aizen
//
//  Orchestrates MCP server installation, removal, and status tracking
//  Uses config file-based management for all agents
//

import Combine
import Foundation

// MARK: - MCP Manager

@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()

    @Published var installedServers: [String: [MCPInstalledServer]] = [:]
    @Published var isSyncing: Set<String> = []
    @Published var isInstalling = false
    @Published var isRemoving = false
    @Published var lastError: MCPManagerError?

    private let configManager = MCPConfigManager.shared

    private init() {}

    // MARK: - Install Package

    func installPackage(
        server: MCPServer,
        package: MCPPackage,
        agentId: String,
        agentPath: String?,
        env: [String: String]
    ) async throws {
        isInstalling = true
        lastError = nil
        defer { isInstalling = false }

        let serverName = extractServerName(from: server.name)

        // Build stdio config for package
        let (command, args) = runtimeCommand(for: package)
        let config = MCPServerEntry.stdio(command: command, args: args, env: env)

        try await configManager.addServer(name: serverName, config: config, agentId: agentId)

        // Refresh installed list
        await syncInstalled(agentId: agentId, agentPath: agentPath)
    }

    // MARK: - Install Remote

    func installRemote(
        server: MCPServer,
        remote: MCPRemote,
        agentId: String,
        agentPath: String?,
        env: [String: String]
    ) async throws {
        isInstalling = true
        lastError = nil
        defer { isInstalling = false }

        let serverName = extractServerName(from: server.name)

        // Build http/sse config for remote
        let config: MCPServerEntry
        if remote.type == "sse" {
            config = MCPServerEntry.sse(url: remote.url)
        } else {
            config = MCPServerEntry.http(url: remote.url)
        }

        try await configManager.addServer(name: serverName, config: config, agentId: agentId)

        // Refresh installed list
        await syncInstalled(agentId: agentId, agentPath: agentPath)
    }

    // MARK: - Remove

    func remove(serverName: String, agentId: String, agentPath: String?) async throws {
        isRemoving = true
        lastError = nil
        defer { isRemoving = false }

        try await configManager.removeServer(name: serverName, agentId: agentId)

        // Refresh installed list
        await syncInstalled(agentId: agentId, agentPath: agentPath)
    }

    // MARK: - Sync

    func syncInstalled(agentId: String, agentPath: String?) async {
        isSyncing.insert(agentId)
        defer { isSyncing.remove(agentId) }

        let servers = await configManager.listServers(agentId: agentId)

        let installed = servers.map { (name, config) in
            MCPInstalledServer(
                serverName: name,
                displayName: name,
                agentId: agentId,
                packageType: config.command != nil ? "stdio" : nil,
                transportType: config.type,
                configuredEnv: config.env ?? [:]
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

    // MARK: - Support Check

    static func supportsMCPManagement(agentId: String) -> Bool {
        switch agentId {
        case "claude", "codex", "gemini", "opencode", "kimi":
            return true
        default:
            return false
        }
    }

    // MARK: - Private Helpers

    private func extractServerName(from fullName: String) -> String {
        if let lastComponent = fullName.split(separator: "/").last {
            return String(lastComponent)
        }
        return fullName
    }

    private func runtimeCommand(for package: MCPPackage) -> (String, [String]) {
        var args: [String] = []

        switch package.registryType {
        case "npm":
            args.append("-y")
            args.append(package.identifier)
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs)
            }
            return (package.runtimeHint, args)  // npx

        case "pypi":
            args.append(package.identifier)
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs)
            }
            return (package.runtimeHint, args)  // uvx

        case "oci":
            args.append("run")
            args.append("-i")
            args.append("--rm")
            args.append(package.identifier)
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs)
            }
            return ("docker", args)

        default:
            args.append(package.identifier)
            if let runtimeArgs = package.runtimeArguments {
                args.append(contentsOf: runtimeArgs)
            }
            return (package.runtimeHint, args)
        }
    }
}

// MARK: - Errors

enum MCPManagerError: LocalizedError {
    case configError(String)
    case agentNotFound(String)

    var errorDescription: String? {
        switch self {
        case .configError(let reason):
            return "Config error: \(reason)"
        case .agentNotFound(let agentId):
            return "Agent not found: \(agentId)"
        }
    }
}
