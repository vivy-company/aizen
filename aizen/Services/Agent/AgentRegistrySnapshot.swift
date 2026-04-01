//
//  AgentRegistrySnapshot.swift
//  aizen
//
//  Immutable registry state for agent metadata.
//

import Foundation

nonisolated struct AgentRegistrySnapshot: Sendable {
    var metadataById: [String: AgentMetadata]

    static let empty = AgentRegistrySnapshot(metadataById: [:])

    var allAgents: [AgentMetadata] {
        Array(metadataById.values)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var enabledAgents: [AgentMetadata] {
        allAgents.filter { $0.isEnabled }
    }

    func metadata(for agentId: String) -> AgentMetadata? {
        metadataById[agentId]
    }

    func updating(_ metadata: AgentMetadata) -> AgentRegistrySnapshot {
        var next = metadataById
        next[metadata.id] = metadata
        return AgentRegistrySnapshot(metadataById: next)
    }

    func removing(agentId: String) -> AgentRegistrySnapshot {
        var next = metadataById
        next.removeValue(forKey: agentId)
        return AgentRegistrySnapshot(metadataById: next)
    }

    func merged(with defaultAgents: [AgentMetadata]) -> AgentRegistrySnapshot {
        var next = metadataById.filter { _, agent in
            agent.source == .custom || agent.source == .registry
        }

        for agent in defaultAgents {
            if let existing = next[agent.id] {
                var merged = agent
                merged.isEnabled = existing.isEnabled
                merged.environmentVariables = existing.environmentVariables
                next[agent.id] = merged
            } else {
                next[agent.id] = agent
            }
        }

        return AgentRegistrySnapshot(metadataById: next)
    }
}
