//
//  AgentDefaults.swift
//  aizen
//

import Foundation

extension AgentRegistry {
    nonisolated static let managedAgentsBasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aizen/agents"
    }()

    nonisolated static let defaultAgentID = "claude-acp"

    func initializeDefaultAgents() async {
        await bootstrapDefaultAgents()
    }
}
