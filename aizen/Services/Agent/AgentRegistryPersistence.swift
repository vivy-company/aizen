//
//  AgentRegistryPersistence.swift
//  aizen
//
//  UserDefaults-backed persistence for agent registry state.
//

import Foundation

nonisolated enum AgentRegistryPersistence {
    static let metadataStoreKey = "agentMetadataStore"
    static let authPreferencesKey = "acpAgentAuthPreferences"

    static func loadSnapshot(defaults: UserDefaults = .standard) -> AgentRegistrySnapshot {
        guard let data = defaults.data(forKey: metadataStoreKey) else {
            return .empty
        }

        do {
            let decoded = try JSONDecoder().decode([String: AgentMetadata].self, from: data)
            let validated = validStoredMetadata(decoded)
            if validated.count != decoded.count {
                saveSnapshot(AgentRegistrySnapshot(metadataById: validated), defaults: defaults)
            }
            return AgentRegistrySnapshot(metadataById: validated)
        } catch {
            return .empty
        }
    }

    static func saveSnapshot(_ snapshot: AgentRegistrySnapshot, defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(snapshot.metadataById)
            defaults.set(data, forKey: metadataStoreKey)
        } catch {
            // Best effort persistence only.
        }
    }

    static func validStoredMetadata(_ metadata: [String: AgentMetadata]) -> [String: AgentMetadata] {
        metadata.filter { _, agent in
            switch agent.source {
            case .custom:
                return true
            case .registry:
                return agent.registryDistributionType != nil
            }
        }
    }

    static func loadAuthPreferences(defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
    }

    static func saveAuthPreferences(_ preferences: [String: String], defaults: UserDefaults = .standard) {
        defaults.set(preferences, forKey: authPreferencesKey)
    }
}
