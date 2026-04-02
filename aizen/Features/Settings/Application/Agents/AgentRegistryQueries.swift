//
//  AgentRegistryQueries.swift
//  aizen
//
//  Pure query helpers over immutable registry snapshots.
//

import Foundation

nonisolated enum AgentRegistryQueries {
    static func allAgents(
        from snapshot: AgentRegistrySnapshot,
        environmentStore: AgentEnvironmentStore = .shared
    ) -> [AgentMetadata] {
        snapshot.allAgents.map { environmentStore.hydrate($0) }
    }

    static func enabledAgents(
        from snapshot: AgentRegistrySnapshot,
        environmentStore: AgentEnvironmentStore = .shared
    ) -> [AgentMetadata] {
        allAgents(from: snapshot, environmentStore: environmentStore).filter { $0.isEnabled }
    }

    static func metadata(
        for agentId: String,
        from snapshot: AgentRegistrySnapshot,
        environmentStore: AgentEnvironmentStore = .shared
    ) -> AgentMetadata? {
        snapshot.metadata(for: agentId).map { environmentStore.hydrate($0) }
    }

    static func agentPath(for agentName: String, from snapshot: AgentRegistrySnapshot) -> String? {
        guard let metadata = snapshot.metadata(for: agentName) else { return nil }
        if metadata.command != nil {
            return "/usr/bin/env"
        }
        return metadata.executablePath
    }

    static func launchArguments(for agentName: String, from snapshot: AgentRegistrySnapshot) -> [String] {
        guard let metadata = snapshot.metadata(for: agentName) else { return [] }
        if let command = metadata.command {
            return [command] + metadata.launchArgs
        }
        return metadata.launchArgs
    }

    static func launchEnvironment(
        for agentName: String,
        from snapshot: AgentRegistrySnapshot
    ) -> [String: String] {
        guard let metadata = snapshot.metadata(for: agentName) else { return [:] }

        var environment = metadata.baseEnvironment
        let userEnvironment = AgentEnvironmentStore.shared.launchEnvironment(
            from: metadata.environmentVariables,
            agentId: metadata.id
        )

        for (key, value) in userEnvironment {
            environment[key] = value
        }

        return environment
    }

    static func defaultDisplayName(for agentName: String, from snapshot: AgentRegistrySnapshot) -> String {
        metadata(for: agentName, from: snapshot)?.name ?? agentName.capitalized
    }
}
