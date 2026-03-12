//
//  AgentInstaller.swift
//  aizen
//

import Foundation

enum AgentInstallError: LocalizedError {
    case invalidResponse
    case downloadFailed(message: String)
    case installFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response while installing the agent"
        case .downloadFailed(let message):
            return message
        case .installFailed(let message):
            return message
        }
    }
}

actor AgentInstaller {
    static let shared = AgentInstaller()

    private init() {}

    func canInstall(_ metadata: AgentMetadata) -> Bool {
        metadata.requiresInstall
    }

    func isInstalled(_ agentName: String) -> Bool {
        AgentRegistry.shared.validateAgent(named: agentName)
    }

    func canUpdate(_ metadata: AgentMetadata) async -> Bool {
        guard metadata.isRegistry else { return false }
        let versionInfo = await AgentVersionChecker.shared.checkVersion(for: metadata.id)
        return versionInfo.updateAvailable
    }

    func installAgent(_ metadata: AgentMetadata) async throws {
        guard metadata.isRegistry else {
            throw AgentInstallError.installFailed(message: "Only registry agents can be installed automatically")
        }

        if metadata.requiresInstall {
            _ = try await ACPRegistryService.shared.installAgent(metadata)
        }
    }

    func installAgent(_ agentName: String) async throws {
        guard let metadata = AgentRegistry.shared.getMetadata(for: agentName) else {
            throw AgentInstallError.installFailed(message: "Unknown agent: \(agentName)")
        }
        try await installAgent(metadata)
    }

    func updateAgent(_ metadata: AgentMetadata) async throws {
        guard metadata.isRegistry else {
            throw AgentInstallError.installFailed(message: "Only registry agents can be updated automatically")
        }

        let refreshed = await ACPRegistryService.shared.refreshMetadata(for: metadata)
        await AgentRegistry.shared.updateAgent(refreshed)

        if refreshed.requiresInstall {
            _ = try await ACPRegistryService.shared.installAgent(refreshed)
        }
    }

    func uninstallAgent(_ agentName: String) async throws {
        let agentDir = URL(fileURLWithPath: AgentRegistry.managedAgentsBasePath, isDirectory: true)
            .appendingPathComponent(agentName, isDirectory: true)

        if FileManager.default.fileExists(atPath: agentDir.path) {
            try FileManager.default.removeItem(at: agentDir)
        }

        await AgentRegistry.shared.removeAgent(named: agentName)
    }
}
