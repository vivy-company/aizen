//
//  AgentDiscoveryService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Service for validating agent executables
extension AgentRegistry {
    /// Built-in agent IDs
    static let builtInExecutableNames: [String: [String]] = [
        "claude": ["claude-code-acp"],
        "codex": ["codex-acp", "codex"],
        "copilot": ["copilot"],
        "droid": ["droid"],
        "gemini": ["gemini"],
        "kimi": ["kimi"],
        "opencode": ["opencode"],
        "qwen": ["qwen"],
        "vibe": ["vibe-acp"]
    ]

    // MARK: - Validation

    /// Check if agent executable exists and is executable
    nonisolated func validateAgent(named agentName: String) -> Bool {
        guard let path = getAgentPath(for: agentName) else {
            return false
        }

        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
    }
}
