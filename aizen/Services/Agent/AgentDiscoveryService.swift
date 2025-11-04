//
//  AgentDiscoveryService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Service for discovering and validating agent executables
extension AgentRegistry {
    /// Built-in agent executable names for discovery
    static let builtInExecutableNames: [String: [String]] = [
        "claude": ["claude-code-acp"],
        "codex": ["codex-acp", "codex"],
        "gemini": ["gemini"],
        "kimi": ["kimi"]
    ]

    // MARK: - Discovery

    /// Discover agents in common installation locations
    func discoverAgents() -> [String: String] {
        var discovered: [String: String] = [:]

        for (agentName, _) in Self.builtInExecutableNames {
            if let path = discoverAgent(named: agentName) {
                discovered[agentName] = path
            }
        }

        return discovered
    }

    /// Discover path for a specific agent
    func discoverAgent(named agentName: String) -> String? {
        let searchPaths = getSearchPaths(for: agentName)

        if let names = Self.builtInExecutableNames[agentName] {
            for execName in names {
                if let path = findExecutable(named: execName, in: searchPaths) {
                    return path
                }
            }
        }

        // Fallback: try agent name directly
        if let path = findExecutable(named: agentName, in: searchPaths) {
            return path
        }

        return nil
    }

    // MARK: - Validation

    /// Check if agent executable exists and is executable
    func validateAgent(named agentName: String) -> Bool {
        guard let path = getAgentPath(for: agentName) else {
            return false
        }

        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
    }

    /// Validate all configured agents and return status
    func validateAllAgents() -> [String: Bool] {
        var status: [String: Bool] = [:]
        for agentName in agentMetadata.keys {
            status[agentName] = validateAgent(named: agentName)
        }
        return status
    }

    // MARK: - Private Helpers

    /// Get search paths for agent executables
    func getSearchPaths(for agentName: String) -> [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return [
            homeDir.appendingPathComponent(".aizen/agents/\(agentName)").path,
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            homeDir.appendingPathComponent(".local/bin").path,
            homeDir.appendingPathComponent("bin").path,
            homeDir.appendingPathComponent(".cargo/bin").path,
            homeDir.appendingPathComponent(".npm-global/bin").path,
            "/usr/local/lib/node_modules/.bin",
        ]
    }

    /// Find executable in given paths
    func findExecutable(named name: String, in paths: [String]) -> String? {
        let fileManager = FileManager.default

        for directory in paths {
            let fullPath = (directory as NSString).appendingPathComponent(name)
            if fileManager.fileExists(atPath: fullPath) && fileManager.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }
}
