//
//  AgentLaunchResolver.swift
//  aizen
//
//  Pure launch resolution helpers for agent execution.
//

import Foundation

nonisolated struct AgentLaunchResolver {
    func resolvedEnvironment(
        for agentName: String,
        snapshot: AgentRegistrySnapshot
    ) async -> [String: String] {
        guard let metadata = snapshot.metadata(for: agentName) else { return [:] }

        var environment = await ShellEnvironmentLoader.loadShellEnvironment()

        for (key, value) in metadata.baseEnvironment {
            environment[key] = value
        }

        let userEnvironment = AgentEnvironmentStore.shared.launchEnvironment(
            from: metadata.environmentVariables,
            agentId: metadata.id
        )

        for (key, value) in userEnvironment {
            environment[key] = value
        }

        return environment
    }
}
