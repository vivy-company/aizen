//
//  AgentRegistryStore.swift
//  aizen
//
//  Actor-backed persistence boundary for agent metadata.
//

import Foundation

actor AgentRegistryStore {
    private let defaults: UserDefaults
    private var snapshot: AgentRegistrySnapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.snapshot = AgentRegistryPersistence.loadSnapshot(defaults: defaults)
    }

    func loadSnapshot() -> AgentRegistrySnapshot {
        snapshot
    }

    func snapshotMetadata(for agentId: String) -> AgentMetadata? {
        snapshot.metadata(for: agentId)
    }

    func replaceSnapshot(_ nextSnapshot: AgentRegistrySnapshot) -> AgentRegistrySnapshot {
        snapshot = nextSnapshot
        AgentRegistryPersistence.saveSnapshot(snapshot, defaults: defaults)
        return snapshot
    }

    func bootstrapSnapshot(from currentSnapshot: AgentRegistrySnapshot) async -> AgentRegistrySnapshot {
        let defaultAgents = await ACPRegistryService.shared.defaultAgents()
        let merged = currentSnapshot.merged(with: defaultAgents)

        return replaceSnapshot(merged)
    }

    func upsertAgent(_ metadata: AgentMetadata) -> (snapshot: AgentRegistrySnapshot, previous: AgentMetadata?) {
        let previous = snapshot.metadata(for: metadata.id)
        let nextSnapshot = snapshot.updating(metadata)
        return (replaceSnapshot(nextSnapshot), previous)
    }

    func removeAgent(id: String) -> (snapshot: AgentRegistrySnapshot, removed: AgentMetadata?) {
        let removed = snapshot.metadata(for: id)
        let nextSnapshot = snapshot.removing(agentId: id)
        return (replaceSnapshot(nextSnapshot), removed)
    }

    func updateEnabledState(agentId: String, isEnabled: Bool) -> (snapshot: AgentRegistrySnapshot, previous: AgentMetadata?) {
        guard var metadata = snapshot.metadata(for: agentId) else {
            return (snapshot, nil)
        }

        let previous = metadata
        metadata.isEnabled = isEnabled
        let nextSnapshot = snapshot.updating(metadata)
        return (replaceSnapshot(nextSnapshot), previous)
    }
}
