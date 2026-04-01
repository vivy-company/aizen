//
//  AgentAuthPreferences.swift
//  aizen
//
//  UserDefaults-backed auth preference storage for agents.
//

import Foundation

nonisolated final class AgentAuthPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savePreference(agentName: String, authMethodId: String) {
        var preferences = AgentRegistryPersistence.loadAuthPreferences(defaults: defaults)
        preferences[agentName] = authMethodId
        AgentRegistryPersistence.saveAuthPreferences(preferences, defaults: defaults)
    }

    func preference(for agentName: String) -> String? {
        AgentRegistryPersistence.loadAuthPreferences(defaults: defaults)[agentName]
    }

    func saveSkipAuth(for agentName: String) {
        savePreference(agentName: agentName, authMethodId: "skip")
    }

    func shouldSkipAuth(for agentName: String) -> Bool {
        preference(for: agentName) == "skip"
    }

    func clearPreference(for agentName: String) {
        var preferences = AgentRegistryPersistence.loadAuthPreferences(defaults: defaults)
        preferences.removeValue(forKey: agentName)
        AgentRegistryPersistence.saveAuthPreferences(preferences, defaults: defaults)
    }

    func displayableAuthMethodName(for agentName: String) -> String? {
        guard let authMethodId = preference(for: agentName) else {
            return nil
        }

        if authMethodId == "skip" {
            return "None"
        }

        return authMethodId
    }
}
