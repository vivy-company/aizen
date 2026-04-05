import Foundation

extension AgentRegistry {
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
