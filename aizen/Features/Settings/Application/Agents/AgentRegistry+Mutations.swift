import Foundation

extension AgentRegistry {
    // MARK: - Mutation

    func addCustomAgent(
        name: String,
        description: String?,
        iconType: AgentIconType,
        executablePath: String,
        launchArgs: [String],
        environmentVariables: [AgentEnvironmentVariable] = []
    ) async -> AgentMetadata {
        await mutationGate.perform {
            let id = "custom-\(UUID().uuidString)"
            let storedEnvironmentVariables = AgentEnvironmentStore.shared.persistedVariables(
                from: environmentVariables,
                previous: [],
                agentId: id
            )

            let metadata = AgentMetadata(
                id: id,
                name: name,
                description: description,
                iconType: iconType,
                source: .custom,
                isEnabled: true,
                executablePath: executablePath,
                command: nil,
                launchArgs: launchArgs,
                environmentVariables: storedEnvironmentVariables
            )

            let result = await store.upsertAgent(metadata)
            applySnapshot(result.snapshot)
            return AgentEnvironmentStore.shared.hydrate(metadata)
        }
    }

    func upsertRegistryAgent(_ metadata: AgentMetadata) async {
        await updateAgent(metadata)
    }

    func updateAgent(_ metadata: AgentMetadata) async {
        await mutationGate.perform {
            let previousStoredMetadata = await store.snapshotMetadata(for: metadata.id)
            let storedEnvironmentVariables = AgentEnvironmentStore.shared.persistedVariables(
                from: metadata.environmentVariables,
                previous: previousStoredMetadata?.environmentVariables ?? [],
                agentId: metadata.id
            )

            var storedMetadata = metadata
            storedMetadata.environmentVariables = storedEnvironmentVariables

            let result = await store.upsertAgent(storedMetadata)
            applySnapshot(result.snapshot)
        }
    }

    func deleteAgent(id: String) async {
        await mutationGate.perform {
            guard let metadata = await store.snapshotMetadata(for: id),
                  metadata.isCustom || metadata.isRegistry else {
                return
            }

            AgentEnvironmentStore.shared.deleteSecrets(for: metadata.environmentVariables, agentId: metadata.id)

            let result = await store.removeAgent(id: id)
            applySnapshot(result.snapshot)
        }
    }

    func toggleEnabled(for agentId: String) async {
        await mutationGate.perform {
            let current = await store.snapshotMetadata(for: agentId)
            let nextEnabled = !(current?.isEnabled ?? true)
            let result = await store.updateEnabledState(agentId: agentId, isEnabled: nextEnabled)
            applySnapshot(result.snapshot)
        }
    }
}
