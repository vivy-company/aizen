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
    /// This performs basic file system validation only
    func validateAgent(named agentName: String) -> Bool {
        guard let path = getAgentPath(for: agentName) else {
            return false
        }

        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
    }

    /// Validate agent executable and ACP protocol compatibility
    /// This performs comprehensive validation including launch arguments and ACP protocol
    func validateAgentWithProtocol(named agentName: String) async -> (valid: Bool, error: String?) {
        guard let path = getAgentPath(for: agentName) else {
            return (false, "No executable path configured")
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return (false, "Executable file does not exist")
        }

        guard fileManager.isExecutableFile(atPath: path) else {
            return (false, "File is not executable")
        }

        // Get launch arguments for this agent
        let launchArgs = getAgentLaunchArgs(for: agentName)

        // Test ACP protocol compatibility
        do {
            let tempClient = ACPClient()

            try await tempClient.launch(
                agentPath: path,
                arguments: launchArgs
            )

            let capabilities = ClientCapabilities(
                fs: FileSystemCapabilities(
                    readTextFile: true,
                    writeTextFile: true
                ),
                terminal: true
            )

            let initResponse = try await tempClient.initialize(
                protocolVersion: 1,
                capabilities: capabilities
            )

            // If agent requires authentication, that's still valid
            if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
                await tempClient.terminate()
                return (true, nil)
            }

            // Try to create session for agents that don't need auth
            _ = try await tempClient.newSession(
                workingDirectory: FileManager.default.currentDirectoryPath,
                mcpServers: []
            )

            await tempClient.terminate()
            return (true, nil)
        } catch {
            return (false, "ACP protocol validation failed: \(error.localizedDescription)")
        }
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
        var paths = [
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

        // Add NVM paths for Node.js based agents
        if let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"] {
            paths.append(contentsOf: [
                "\(nvmDir)/current/bin",
                "\(nvmDir)/versions/node/*/bin"
            ])
        }

        // Also check common NVM installation locations
        paths.append(contentsOf: [
            homeDir.appendingPathComponent(".local/share/nvm/*/lib/node_modules/.bin").path,
            homeDir.appendingPathComponent(".nvm/versions/node/*/lib/node_modules/.bin").path,
            homeDir.appendingPathComponent(".nvm/versions/node/*/bin").path
        ])

        return paths
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
