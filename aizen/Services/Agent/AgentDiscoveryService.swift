//
//  AgentDiscoveryService.swift
//  aizen
//
//  Validation entry points for agent executables and commands.
//

import Foundation

extension AgentRegistry {
    func validateAgent(named agentName: String) -> Bool {
        guard let metadata = getMetadata(for: agentName) else {
            return false
        }

        return AgentValidator.shared.validate(metadata: metadata)
    }
}
