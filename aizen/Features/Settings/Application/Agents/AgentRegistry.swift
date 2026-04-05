//
//  AgentRegistry.swift
//  aizen
//
//  Coordinator for agent metadata, auth preferences, launch resolution, and validation.
//

import Foundation

extension Notification.Name {
    nonisolated static let agentMetadataDidChange = Notification.Name("agentMetadataDidChange")
}

nonisolated final class AgentRegistry {
    static let shared = AgentRegistry()

    let defaults: UserDefaults
    let store: AgentRegistryStore
    let authPreferences: AgentAuthPreferences
    let launchResolver = AgentLaunchResolver()

    let stateLock = NSLock()
    var cachedSnapshot: AgentRegistrySnapshot
    var bootstrapTask: Task<Void, Never>?
    let mutationGate = AgentRegistryMutationGate()

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.store = AgentRegistryStore(defaults: defaults)
        self.authPreferences = AgentAuthPreferences(defaults: defaults)
        self.cachedSnapshot = AgentRegistryPersistence.loadSnapshot(defaults: defaults)
        applySnapshot(cachedSnapshot, notify: false)

        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            await self.initializeDefaultAgents()
        }
    }

    deinit {
        bootstrapTask?.cancel()
    }

    // MARK: - Snapshot

    func getAllAgents() -> [AgentMetadata] {
        AgentRegistryQueries.allAgents(from: snapshotValue())
    }

    func getEnabledAgents() -> [AgentMetadata] {
        AgentRegistryQueries.enabledAgents(from: snapshotValue())
    }

    func getMetadata(for agentId: String) -> AgentMetadata? {
        AgentRegistryQueries.metadata(for: agentId, from: snapshotValue())
    }

}

actor AgentRegistryMutationGate {
    func perform<T>(_ operation: () async -> T) async -> T {
        await operation()
    }
}
