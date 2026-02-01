//
//  AgentUpdater.swift
//  aizen
//
//  Service to update ACP agents
//

import ACP
import Foundation

enum AgentUpdateError: Error, LocalizedError {
    case updateFailed(String)
    case unsupportedInstallMethod
    case agentNotFound

    var errorDescription: String? {
        switch self {
        case .updateFailed(let message):
            return "Update failed: \(message)"
        case .unsupportedInstallMethod:
            return "This agent's install method does not support updates"
        case .agentNotFound:
            return "Agent not found or has no install method configured"
        }
    }
}

actor AgentUpdater {
    static let shared = AgentUpdater()

    private var updatingAgents: Set<String> = []

    private init() {}

    func isUpdating(agentName: String) -> Bool {
        return updatingAgents.contains(agentName)
    }

    /// Update an agent to the latest version
    func updateAgent(agentName: String) async throws {
        guard let metadata = AgentRegistry.shared.getMetadata(for: agentName) else {
            throw AgentUpdateError.agentNotFound
        }

        // Use AgentInstaller which handles all install methods
        try await AgentInstaller.shared.updateAgent(metadata)

        // Clear version cache after update
        await AgentVersionChecker.shared.clearCache(for: agentName)
    }

    /// Update agent with progress tracking
    func updateAgentWithProgress(
        agentName: String,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws {
        guard !updatingAgents.contains(agentName) else {
            return // Already updating
        }

        updatingAgents.insert(agentName)
        defer { updatingAgents.remove(agentName) }

        guard let metadata = AgentRegistry.shared.getMetadata(for: agentName),
              let installMethod = metadata.installMethod else {
            throw AgentUpdateError.agentNotFound
        }

        let methodName: String
        switch installMethod {
        case .npm(let package):
            methodName = package
        case .uv(let package):
            methodName = package
        case .githubRelease(let repo, _):
            methodName = repo
        case .binary(let url):
            methodName = url
        case .script(let url):
            methodName = url
        }

        await MainActor.run { onProgress("Updating \(methodName)...") }

        do {
            try await AgentInstaller.shared.updateAgent(metadata)
            await AgentVersionChecker.shared.clearCache(for: agentName)
            await MainActor.run { onProgress("Update complete!") }
        } catch {
            await MainActor.run { onProgress("Update failed: \(error.localizedDescription)") }
            throw error
        }
    }
}
