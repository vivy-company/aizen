//
//  ACPRegistryService.swift
//  aizen
//

import ACPRegistry
import Foundation

actor ACPRegistryService {
    static let shared = ACPRegistryService()

    static let defaultSeedAgentIDs = ["claude-acp", "codex-acp", "opencode"]
    static let defaultDisplayNames: [String: String] = [
        "claude-acp": "Claude Code",
        "codex-acp": "Codex",
        "opencode": "OpenCode",
    ]

    private let client: RegistryClient
    private let iconCache = RegistryAgentIconCache.shared
    private let installDirectory: URL

    private init() {
        client = RegistryClient()
        installDirectory = URL(fileURLWithPath: AgentRegistry.managedAgentsBasePath, isDirectory: true)
    }

    func fetchAgents(forceRefresh: Bool = false) async throws -> [RegistryAgent] {
        let registry = try await client.fetch(forceRefresh: forceRefresh)
        return registry.agents
            .filter { $0.distribution.preferred(for: .current) != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func agent(id: String, forceRefresh: Bool = false) async throws -> RegistryAgent? {
        let registry = try await client.fetch(forceRefresh: forceRefresh)
        return registry.agents.first { $0.id == id }
    }

    func addAgent(_ agent: RegistryAgent) async throws -> AgentMetadata {
        let metadata = await makeMetadata(from: agent)
        await AgentRegistry.shared.upsertRegistryAgent(metadata)
        return metadata
    }

    func defaultAgents() async -> [AgentMetadata] {
        var defaults: [AgentMetadata] = []

        for agentID in Self.defaultSeedAgentIDs {
            if let agent = try? await agent(id: agentID) {
                defaults.append(await makeMetadata(from: agent, isEnabled: true))
            }
        }

        return defaults
    }

    func refreshMetadata(for metadata: AgentMetadata) async -> AgentMetadata {
        guard metadata.isRegistry,
              let agent = try? await agent(id: metadata.id, forceRefresh: true) else {
            return metadata
        }

        var refreshed = await makeMetadata(from: agent, isEnabled: metadata.isEnabled)
        refreshed.environmentVariables = metadata.environmentVariables
        return refreshed
    }

    func installAgent(_ metadata: AgentMetadata) async throws -> AgentMetadata {
        guard metadata.registryDistributionType == .binary,
              let agent = try await agent(id: metadata.id, forceRefresh: true) else {
            throw RegistryError.agentNotFound(metadata.id)
        }

        let installer = ACPRegistry.AgentInstaller(installDirectory: installDirectory)
        let installed = try await installer.install(agent)

        var updated = await makeMetadata(from: agent, isEnabled: metadata.isEnabled)
        updated.executablePath = installed.executablePath
        updated.launchArgs = installed.arguments
        updated.baseEnvironment = installed.environment
        updated.environmentVariables = metadata.environmentVariables
        await AgentRegistry.shared.updateAgent(updated)
        return updated
    }

    private func makeMetadata(from agent: RegistryAgent, isEnabled: Bool = true) async -> AgentMetadata {
        let preferredMethod = agent.distribution.preferred(for: .current)
        let iconData = await iconCache.iconData(for: agent.icon)
        let iconType: AgentIconType =
            if let iconData, !RegistryAgentIconCache.isSVGData(iconData) {
                .customImage(iconData)
            } else {
                .sfSymbol("brain.head.profile")
            }

        var executablePath: String?
        var command: String?
        var launchArgs: [String] = []
        var baseEnvironment: [String: String] = [:]
        var distributionType: RegistryDistributionType?

        switch preferredMethod {
        case .binary(let target):
            executablePath = Self.managedBinaryPath(agentID: agent.id, commandPath: target.cmd)
            launchArgs = target.args ?? []
            baseEnvironment = target.env ?? [:]
            distributionType = .binary
        case .npx(let package):
            command = "npx"
            launchArgs = [package.package] + (package.args ?? [])
            baseEnvironment = package.env ?? [:]
            distributionType = .npx
        case .uvx(let package):
            command = "uvx"
            launchArgs = [package.package] + (package.args ?? [])
            baseEnvironment = package.env ?? [:]
            distributionType = .uvx
        case .none:
            break
        }

        let displayName = Self.defaultDisplayNames[agent.id] ?? agent.name

        return AgentMetadata(
            id: agent.id,
            name: displayName,
            description: agent.description,
            iconType: iconType,
            source: .registry,
            isEnabled: isEnabled,
            executablePath: executablePath,
            command: command,
            launchArgs: launchArgs,
            baseEnvironment: baseEnvironment,
            registryVersion: agent.version,
            registryRepositoryURL: agent.repository,
            registryIconURL: agent.icon,
            registryDistributionType: distributionType
        )
    }

    static func managedBinaryPath(agentID: String, commandPath: String) -> String {
        let sanitizedCommandPath = commandPath
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "./", with: "")
        return URL(fileURLWithPath: AgentRegistry.managedAgentsBasePath, isDirectory: true)
            .appendingPathComponent(agentID, isDirectory: true)
            .appendingPathComponent(sanitizedCommandPath)
            .path
    }
}
