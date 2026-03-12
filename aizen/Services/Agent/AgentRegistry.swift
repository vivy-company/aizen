//
//  AgentRegistry.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Foundation
import SwiftUI

extension Notification.Name {
    static let agentMetadataDidChange = Notification.Name("agentMetadataDidChange")
}

enum AgentRegistryError: Error, LocalizedError {
    case agentNotFound
    
    var errorDescription: String? {
        switch self {
        case .agentNotFound: return "Agent not found"
        }
    }
}

/// Manages discovery and configuration of available ACP agents
actor AgentRegistry {
    static let shared = AgentRegistry()

    // SAFETY: UserDefaults is thread-safe for read/write operations
    private nonisolated(unsafe) let defaults: UserDefaults
    private let authPreferencesKey = "acpAgentAuthPreferences"
    private let metadataStoreKey = "agentMetadataStore"

    // MARK: - Persistence

    /// Agent metadata storage with in-memory cache
    private var metadataCache: [String: AgentMetadata]?
    private static var cachedMetadata: [String: AgentMetadata] = [:]
    private static var cacheLoaded: Bool = false
    private static let cacheLock = NSLock()

    internal var agentMetadata: [String: AgentMetadata] {
        get {
            if let cache = metadataCache {
                Self.updateNonisolatedCache(cache)
                return cache
            }

            guard let data = defaults.data(forKey: metadataStoreKey) else {
                Self.updateNonisolatedCache([:])
                return [:]
            }

            do {
                let decoder = JSONDecoder()
                let decoded = try decoder.decode([String: AgentMetadata].self, from: data)
                let validated = Self.validStoredMetadata(decoded)
                if validated.count != decoded.count {
                    persistValidatedMetadata(validated)
                }
                metadataCache = validated
                Self.updateNonisolatedCache(validated)
                return validated
            } catch {
                Self.updateNonisolatedCache([:])
                return [:]
            }
        }
        set {
            metadataCache = newValue
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(newValue)
                defaults.set(data, forKey: metadataStoreKey)
                Self.updateNonisolatedCache(newValue)
                Task { @MainActor in
                    NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
                }
            } catch {
                // Ignore encoding failure - metadata will be stale but not lost
            }
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Task {
            await initializeDefaultAgents()
        }
    }

    // MARK: - Metadata Management

    /// Load metadata directly from UserDefaults (thread-safe)
    private nonisolated func loadMetadataFromDefaults() -> [String: AgentMetadata] {
        if let cached = Self.readNonisolatedCache() {
            return cached
        }

        guard let data = defaults.data(forKey: metadataStoreKey) else {
            Self.updateNonisolatedCache([:])
            return [:]
        }

        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode([String: AgentMetadata].self, from: data)
            let validated = Self.validStoredMetadata(decoded)
            if validated.count != decoded.count {
                persistValidatedMetadata(validated)
            }
            Self.updateNonisolatedCache(validated)
            return validated
        } catch {
            Self.updateNonisolatedCache([:])
            return [:]
        }
    }

    private nonisolated func persistValidatedMetadata(_ metadata: [String: AgentMetadata]) {
        do {
            let data = try JSONEncoder().encode(metadata)
            defaults.set(data, forKey: metadataStoreKey)
        } catch {
        }
    }

    private nonisolated static func readNonisolatedCache() -> [String: AgentMetadata]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard cacheLoaded else { return nil }
        return cachedMetadata
    }

    private nonisolated static func updateNonisolatedCache(_ metadata: [String: AgentMetadata]) {
        cacheLock.lock()
        cachedMetadata = metadata
        cacheLoaded = true
        cacheLock.unlock()
    }

    private nonisolated static func validStoredMetadata(_ metadata: [String: AgentMetadata]) -> [String: AgentMetadata] {
        metadata.filter { _, agent in
            switch agent.source {
            case .custom:
                return true
            case .registry:
                return agent.registryDistributionType != nil
            }
        }
    }

    /// Get all agents (enabled and disabled)
    nonisolated func getAllAgents() -> [AgentMetadata] {
        let metadata = loadMetadataFromDefaults()
        return Array(metadata.values)
            .map { AgentEnvironmentStore.shared.hydrate($0) }
            .sorted { $0.name < $1.name }
    }

    /// Get only enabled agents
    nonisolated func getEnabledAgents() -> [AgentMetadata] {
        getAllAgents().filter { $0.isEnabled }
    }

    /// Get metadata for specific agent
    nonisolated func getMetadata(for agentId: String) -> AgentMetadata? {
        let metadata = loadMetadataFromDefaults()
        guard let stored = metadata[agentId] else { return nil }
        return AgentEnvironmentStore.shared.hydrate(stored)
    }

    /// Add custom agent
    func addCustomAgent(
        name: String,
        description: String?,
        iconType: AgentIconType,
        executablePath: String,
        launchArgs: [String],
        environmentVariables: [AgentEnvironmentVariable] = []
    ) -> AgentMetadata {
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

        var store = agentMetadata
        store[id] = metadata
        agentMetadata = store

        return AgentEnvironmentStore.shared.hydrate(metadata)
    }

    func upsertRegistryAgent(_ metadata: AgentMetadata) {
        updateAgent(metadata)
    }

    /// Update agent metadata
    func updateAgent(_ metadata: AgentMetadata) {
        let previousStoredMetadata = agentMetadata[metadata.id]
        let storedEnvironmentVariables = AgentEnvironmentStore.shared.persistedVariables(
            from: metadata.environmentVariables,
            previous: previousStoredMetadata?.environmentVariables ?? [],
            agentId: metadata.id
        )

        var storedMetadata = metadata
        storedMetadata.environmentVariables = storedEnvironmentVariables

        var store = agentMetadata
        store[storedMetadata.id] = storedMetadata
        agentMetadata = store
    }

    /// Delete custom agent
    func deleteAgent(id: String) {
        guard let metadata = agentMetadata[id], metadata.isCustom || metadata.isRegistry else {
            return
        }

        AgentEnvironmentStore.shared.deleteSecrets(for: metadata.environmentVariables, agentId: metadata.id)

        var store = agentMetadata
        store.removeValue(forKey: id)
        agentMetadata = store
    }

    /// Toggle agent enabled status
    func toggleEnabled(for agentId: String) {
        guard var metadata = getMetadata(for: agentId) else {
            return
        }

        metadata.isEnabled = !metadata.isEnabled
        updateAgent(metadata)
    }

    // MARK: - Agent Path Management

    /// Get executable path for a specific agent by name
    nonisolated func getAgentPath(for agentName: String) -> String? {
        let metadata = loadMetadataFromDefaults()
        guard let metadata = metadata[agentName] else { return nil }
        if metadata.command != nil {
            return "/usr/bin/env"
        }
        return metadata.executablePath
    }

    /// Get launch arguments for a specific agent
    nonisolated func getAgentLaunchArgs(for agentName: String) -> [String] {
        let metadata = loadMetadataFromDefaults()
        guard let metadata = metadata[agentName] else { return [] }
        if let command = metadata.command {
            return [command] + metadata.launchArgs
        }
        return metadata.launchArgs
    }

    /// Get environment overrides for a specific agent launch
    nonisolated func getAgentLaunchEnvironment(for agentName: String) -> [String: String] {
        let metadata = loadMetadataFromDefaults()
        guard let storedMetadata = metadata[agentName] else { return [:] }
        var launchEnvironment = storedMetadata.baseEnvironment
        let userEnvironment = AgentEnvironmentStore.shared.launchEnvironment(
            from: storedMetadata.environmentVariables,
            agentId: storedMetadata.id
        )
        for (key, value) in userEnvironment {
            launchEnvironment[key] = value
        }
        return launchEnvironment
    }

    /// Set executable path for a specific agent
    func setAgentPath(_ path: String, for agentName: String) {
        guard var metadata = getMetadata(for: agentName) else {
            return
        }

        metadata.executablePath = path
        updateAgent(metadata)
    }

    /// Remove agent configuration
    func removeAgent(named agentName: String) {
        deleteAgent(id: agentName)
    }

    /// Get list of all available agent names
    func getAvailableAgents() -> [String] {
        return agentMetadata.keys.sorted()
    }

    // MARK: - Auth Preferences

    /// Save preferred auth method for an agent
    nonisolated func saveAuthPreference(agentName: String, authMethodId: String) {
        var prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        prefs[agentName] = authMethodId
        defaults.set(prefs, forKey: authPreferencesKey)
    }

    /// Get saved auth preference for an agent
    nonisolated func getAuthPreference(for agentName: String) -> String? {
        let prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        return prefs[agentName]
    }

    /// Save that an agent should skip authentication
    nonisolated func saveSkipAuth(for agentName: String) {
        saveAuthPreference(agentName: agentName, authMethodId: "skip")
    }

    /// Check if agent should skip authentication
    nonisolated func shouldSkipAuth(for agentName: String) -> Bool {
        return getAuthPreference(for: agentName) == "skip"
    }

    /// Clear saved auth preference for an agent
    nonisolated func clearAuthPreference(for agentName: String) {
        var prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        prefs.removeValue(forKey: agentName)
        defaults.set(prefs, forKey: authPreferencesKey)
    }

    /// Get displayable auth method name for an agent
    nonisolated func getAuthMethodName(for agentName: String) -> String? {
        guard let authMethodId = getAuthPreference(for: agentName) else {
            return nil
        }

        if authMethodId == "skip" {
            return "None"
        }

        return authMethodId
    }
}
