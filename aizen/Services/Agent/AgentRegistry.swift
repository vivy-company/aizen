//
//  AgentRegistry.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import SwiftUI
import os.log

extension Notification.Name {
    static let agentMetadataDidChange = Notification.Name("agentMetadataDidChange")
}

/// Manages discovery and configuration of available ACP agents
actor AgentRegistry {
    static let shared = AgentRegistry()

    private let defaults: UserDefaults
    private let authPreferencesKey = "acpAgentAuthPreferences"
    private let metadataStoreKey = "agentMetadataStore"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "AgentRegistry")

    // MARK: - Persistence

    /// Agent metadata storage with in-memory cache
    private var metadataCache: [String: AgentMetadata]?

    internal var agentMetadata: [String: AgentMetadata] {
        get {
            if let cache = metadataCache {
                return cache
            }

            guard let data = defaults.data(forKey: metadataStoreKey) else {
                return [:]
            }

            do {
                let decoder = JSONDecoder()
                let decoded = try decoder.decode([String: AgentMetadata].self, from: data)
                metadataCache = decoded
                return decoded
            } catch {
                logger.error("Failed to decode agent metadata: \(error.localizedDescription)")
                return [:]
            }
        }
        set {
            metadataCache = newValue
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(newValue)
                defaults.set(data, forKey: metadataStoreKey)
                Task { @MainActor in
                    NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
                }
            } catch {
                logger.error("Failed to encode agent metadata: \(error.localizedDescription)")
            }
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        initializeDefaultAgents()
    }

    // MARK: - Metadata Management

    /// Get all agents (enabled and disabled)
    func getAllAgents() -> [AgentMetadata] {
        Array(agentMetadata.values).sorted { $0.name < $1.name }
    }

    /// Get only enabled agents
    func getEnabledAgents() -> [AgentMetadata] {
        getAllAgents().filter { $0.isEnabled }
    }

    /// Get metadata for specific agent
    func getMetadata(for agentId: String) -> AgentMetadata? {
        return agentMetadata[agentId]
    }

    /// Add custom agent
    func addCustomAgent(
        name: String,
        description: String?,
        iconType: AgentIconType,
        executablePath: String,
        launchArgs: [String]
    ) -> AgentMetadata {
        let id = "custom-\(UUID().uuidString)"
        let metadata = AgentMetadata(
            id: id,
            name: name,
            description: description,
            iconType: iconType,
            isBuiltIn: false,
            isEnabled: true,
            executablePath: executablePath,
            launchArgs: launchArgs,
            installMethod: nil
        )

        var store = agentMetadata
        store[id] = metadata
        agentMetadata = store

        return metadata
    }

    /// Update agent metadata
    func updateAgent(_ metadata: AgentMetadata) {
        var store = agentMetadata
        store[metadata.id] = metadata
        agentMetadata = store
    }

    /// Delete custom agent
    func deleteAgent(id: String) {
        guard let metadata = agentMetadata[id], !metadata.isBuiltIn else {
            return
        }

        var store = agentMetadata
        store.removeValue(forKey: id)
        agentMetadata = store
    }

    /// Toggle agent enabled status
    func toggleEnabled(for agentId: String) {
        guard var metadata = agentMetadata[agentId] else {
            return
        }

        metadata.isEnabled = !metadata.isEnabled

        var store = agentMetadata
        store[agentId] = metadata
        agentMetadata = store
    }

    // MARK: - Agent Path Management

    /// Get executable path for a specific agent by name
    func getAgentPath(for agentName: String) -> String? {
        return agentMetadata[agentName]?.executablePath
    }

    /// Get launch arguments for a specific agent
    func getAgentLaunchArgs(for agentName: String) -> [String] {
        return agentMetadata[agentName]?.launchArgs ?? []
    }

    /// Set executable path for a specific agent
    func setAgentPath(_ path: String, for agentName: String) {
        guard var metadata = agentMetadata[agentName] else {
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
    func saveAuthPreference(agentName: String, authMethodId: String) {
        var prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        prefs[agentName] = authMethodId
        defaults.set(prefs, forKey: authPreferencesKey)
    }

    /// Get saved auth preference for an agent
    func getAuthPreference(for agentName: String) -> String? {
        let prefs = defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
        return prefs[agentName]
    }

    /// Save that an agent should skip authentication
    func saveSkipAuth(for agentName: String) {
        saveAuthPreference(agentName: agentName, authMethodId: "skip")
    }

    /// Check if agent should skip authentication
    func shouldSkipAuth(for agentName: String) -> Bool {
        return getAuthPreference(for: agentName) == "skip"
    }
}
