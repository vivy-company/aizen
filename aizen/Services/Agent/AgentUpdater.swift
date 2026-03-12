//
//  AgentUpdater.swift
//  aizen
//
//  Service to update ACP agents
//

import Foundation

enum AgentUpdateError: Error, LocalizedError {
    case updateFailed(String)
    case agentNotFound

    var errorDescription: String? {
        switch self {
        case .updateFailed(let message):
            return "Update failed: \(message)"
        case .agentNotFound:
            return "Agent not found"
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

        guard let metadata = AgentRegistry.shared.getMetadata(for: agentName) else {
            throw AgentUpdateError.agentNotFound
        }

        await MainActor.run { onProgress("Updating \(metadata.name)...") }

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
