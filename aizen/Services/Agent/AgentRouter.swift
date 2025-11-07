import Foundation
import SwiftUI
import Combine

@MainActor
class AgentRouter: ObservableObject {
    @Published var activeSessions: [String: AgentSession] = [:]

    private let defaultAgentKey = "defaultACPAgent"

    // Cache for fast agent lookup by ID or name
    private var enabledAgentLookup: [String: AgentMetadata] = [:]

    var defaultAgent: String {
        get {
            UserDefaults.standard.string(forKey: defaultAgentKey) ?? "claude"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultAgentKey)
        }
    }

    init() {
        // Listen for agent metadata changes
        NotificationCenter.default.addObserver(
            forName: .agentMetadataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.rebuildLookupCache()
            }
        }

        // Initialize async
        Task {
            await self.rebuildLookupCache()
            await self.initializeSessions()
        }
    }

    private func rebuildLookupCache() async {
        enabledAgentLookup.removeAll()
        let enabledAgents = await AgentRegistry.shared.getEnabledAgents()
        for agent in enabledAgents {
            enabledAgentLookup[agent.id.lowercased()] = agent
            enabledAgentLookup[agent.name.lowercased()] = agent
        }
    }

    private func initializeSessions() async {
        let enabledAgents = await AgentRegistry.shared.getEnabledAgents()
        for agent in enabledAgents {
            activeSessions[agent.id] = AgentSession(agentName: agent.id)
        }
    }

    @MainActor
    func parseAndRoute(message: String) -> (agentName: String, cleanedMessage: String) {
        let pattern = "^@(\\w+)\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (defaultAgent, message)
        }

        let nsRange = NSRange(message.startIndex..., in: message)

        if let match = regex.firstMatch(in: message, options: [], range: nsRange) {
            if let mentionRange = Range(match.range(at: 1), in: message) {
                let mentionedAgent = String(message[mentionRange]).lowercased()

                // Use cached lookup for O(1) performance
                if let matchingAgent = enabledAgentLookup[mentionedAgent] {
                    let cleanedMessage = regex.stringByReplacingMatches(
                        in: message,
                        options: [],
                        range: nsRange,
                        withTemplate: ""
                    ).trimmingCharacters(in: .whitespaces)

                    Task {
                        await ensureSession(for: matchingAgent.id)
                    }
                    return (matchingAgent.id, cleanedMessage)
                }
            }
        }

        return (defaultAgent, message)
    }

    func getSession(for agentName: String) -> AgentSession? {
        return activeSessions[agentName]
    }

    func ensureSession(for agentName: String) async {
        if activeSessions[agentName] == nil {
            // Only create session if agent is enabled
            if let metadata = AgentRegistry.shared.getMetadata(for: agentName),
               metadata.isEnabled {
                activeSessions[agentName] = AgentSession(agentName: agentName)
            }
        }
    }

    func removeSession(for agentName: String) {
        activeSessions.removeValue(forKey: agentName)
    }

    func clearAllSessions() {
        activeSessions.removeAll()
    }
}
