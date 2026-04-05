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
    private let authPreferences: AgentAuthPreferences
    private let launchResolver = AgentLaunchResolver()

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

    // MARK: - Launch

    func getAgentPath(for agentName: String) -> String? {
        AgentRegistryQueries.agentPath(for: agentName, from: snapshotValue())
    }

    func getAgentLaunchArgs(for agentName: String) -> [String] {
        AgentRegistryQueries.launchArguments(for: agentName, from: snapshotValue())
    }

    func getAgentLaunchEnvironment(for agentName: String) -> [String: String] {
        AgentRegistryQueries.launchEnvironment(for: agentName, from: snapshotValue())
    }

    func resolvedAgentLaunchEnvironment(for agentName: String) async -> [String: String] {
        await launchResolver.resolvedEnvironment(for: agentName, snapshot: snapshotValue())
    }

    // MARK: - Auth Preferences

    func saveAuthPreference(agentName: String, authMethodId: String) {
        authPreferences.savePreference(agentName: agentName, authMethodId: authMethodId)
    }

    func getAuthPreference(for agentName: String) -> String? {
        authPreferences.preference(for: agentName)
    }

    func saveSkipAuth(for agentName: String) {
        authPreferences.saveSkipAuth(for: agentName)
    }

    func shouldSkipAuth(for agentName: String) -> Bool {
        authPreferences.shouldSkipAuth(for: agentName)
    }

    func clearAuthPreference(for agentName: String) {
        authPreferences.clearPreference(for: agentName)
    }

    func getAuthMethodName(for agentName: String) -> String? {
        authPreferences.displayableAuthMethodName(for: agentName)
    }

}

actor AgentRegistryMutationGate {
    func perform<T>(_ operation: () async -> T) async -> T {
        await operation()
    }
}
