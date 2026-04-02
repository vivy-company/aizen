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
        if let metadata = AgentRegistry.shared.getMetadata(for: agentName) {
            if metadata.isRegistry {
                try await installAgent(metadata)
                return
            }

            throw AgentInstallError.installFailed(
                message: "\(metadata.name) cannot be installed automatically. Configure its executable in Settings."
            )
        }

        if let registryAgent = try await ACPRegistryService.shared.agent(id: agentName, forceRefresh: true) {
            let metadata = try await ACPRegistryService.shared.addAgent(registryAgent)
            try await installAgent(metadata)
            return
        }

        throw AgentInstallError.installFailed(
            message: "This session's agent is no longer available. Choose another agent or add it again from the registry."
        )
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
}
