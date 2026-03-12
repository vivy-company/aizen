//
//  AgentEnvironmentStore.swift
//  aizen
//
//  Handles hydration and secure persistence of agent environment variables.
//

import Foundation

final class AgentEnvironmentStore {
    nonisolated static let shared = AgentEnvironmentStore()

    nonisolated private let keychain = KeychainStore(service: "win.aizen.app.agent-environment")

    private init() {}

    nonisolated func hydrate(_ metadata: AgentMetadata) -> AgentMetadata {
        var copy = metadata
        copy.environmentVariables = hydratedVariables(metadata.environmentVariables, agentId: metadata.id)
        return copy
    }

    nonisolated func hydratedVariables(_ variables: [AgentEnvironmentVariable], agentId: String) -> [AgentEnvironmentVariable] {
        variables.map { variable in
            guard variable.isSecret else { return variable }

            var hydrated = variable
            hydrated.value = keychain.get(secretKey(agentId: agentId, variableId: variable.id)) ?? ""
            return hydrated
        }
    }

    nonisolated func persistedVariables(
        from variables: [AgentEnvironmentVariable],
        previous previousVariables: [AgentEnvironmentVariable],
        agentId: String
    ) -> [AgentEnvironmentVariable] {
        let cleanedVariables = variables.persistedVariables
        let activeVariableIDs = Set(cleanedVariables.map(\.id))

        for previousVariable in previousVariables where previousVariable.isSecret && !activeVariableIDs.contains(previousVariable.id) {
            keychain.delete(secretKey(agentId: agentId, variableId: previousVariable.id))
        }

        return cleanedVariables.map { variable in
            var persisted = variable
            let key = secretKey(agentId: agentId, variableId: variable.id)

            if variable.isSecret {
                if variable.value.isEmpty {
                    keychain.delete(key)
                } else {
                    try? keychain.set(variable.value, for: key)
                }
                persisted.value = ""
            } else {
                keychain.delete(key)
            }

            return persisted
        }
    }

    nonisolated func launchEnvironment(from storedVariables: [AgentEnvironmentVariable], agentId: String) -> [String: String] {
        hydratedVariables(storedVariables, agentId: agentId).launchEnvironment
    }

    nonisolated func deleteSecrets(for variables: [AgentEnvironmentVariable], agentId: String) {
        for variable in variables where variable.isSecret {
            keychain.delete(secretKey(agentId: agentId, variableId: variable.id))
        }
    }

    nonisolated private func secretKey(agentId: String, variableId: UUID) -> String {
        "agent.\(agentId).env.\(variableId.uuidString)"
    }
}
