//
//  AgentDefaults.swift
//  aizen
//

import Foundation

extension AgentRegistry {
    static let managedAgentsBasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aizen/agents"
    }()

    static let defaultAgentID = "claude-acp"

    func initializeDefaultAgents() async {
        var metadata = agentMetadata.filter { _, agent in
            agent.source == .custom || agent.source == .registry
        }

        let defaultAgents = await ACPRegistryService.shared.defaultAgents()
        for agent in defaultAgents {
            if let existing = metadata[agent.id] {
                var merged = agent
                merged.isEnabled = existing.isEnabled
                merged.environmentVariables = existing.environmentVariables
                metadata[agent.id] = merged
            } else {
                metadata[agent.id] = agent
            }
        }

        agentMetadata = metadata

        let defaultAgent = UserDefaults.standard.string(forKey: "defaultACPAgent")
        if defaultAgent == nil || metadata[defaultAgent ?? ""] == nil {
            UserDefaults.standard.set(Self.defaultAgentID, forKey: "defaultACPAgent")
        }
    }
}
