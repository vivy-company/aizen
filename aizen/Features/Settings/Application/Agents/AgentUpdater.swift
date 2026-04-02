//
//  AgentUpdater.swift
//  aizen
//
//  Service to update ACP agents
//

import Foundation

enum AgentUpdateError: Error, LocalizedError {
    case agentNotFound

    var errorDescription: String? {
        switch self {
        case .agentNotFound:
            return "Agent not found"
        }
    }
}

actor AgentUpdater {
    static let shared = AgentUpdater()

    private var updatingAgents: Set<String> = []

    private init() {}

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
