//
//  AgentDefaults.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Default agent configurations
extension AgentRegistry {
    /// Base path for managed agent installations
    static let managedAgentsBasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aizen/agents"
    }()

    /// Get the managed executable path for a built-in agent
    /// Returns the path where the agent should be installed, regardless of whether it exists
    static func managedPath(for agentId: String) -> String {
        let basePath = managedAgentsBasePath
        switch agentId {
        case "claude":
            return "\(basePath)/claude/node_modules/.bin/claude-code-acp"
        case "codex":
            return "\(basePath)/codex/node_modules/.bin/codex-acp"
        case "gemini":
            return "\(basePath)/gemini/node_modules/.bin/gemini"
        case "kimi":
            return "\(basePath)/kimi/kimi"
        case "opencode":
            return "\(basePath)/opencode/node_modules/.bin/opencode"
        case "vibe":
            return "\(basePath)/vibe/vibe-acp"
        case "qwen":
            return "\(basePath)/qwen/node_modules/.bin/qwen"
        default:
            return "\(basePath)/\(agentId)/\(agentId)"
        }
    }

    /// Check if a built-in agent is installed at the managed path
    static func isInstalledAtManagedPath(_ agentId: String) -> Bool {
        let path = managedPath(for: agentId)
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Initialize default built-in agents
    /// Built-in agents always use managed paths - no discovery
    func initializeDefaultAgents() {
        var metadata = agentMetadata

        // Remove obsolete built-in agents that are no longer in our list
        metadata = metadata.filter { id, agent in
            if !agent.isBuiltIn {
                return true
            }
            return Self.builtInExecutableNames.keys.contains(id)
        }

        // Create or update default built-in agents
        // Always use managed paths for built-ins
        updateBuiltInAgent("claude", in: &metadata) {
            AgentMetadata(
                id: "claude",
                name: "Claude",
                description: "Agentic coding tool that understands your codebase",
                iconType: .builtin("claude"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "claude"),
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/claude-code-acp")
            )
        }

        updateBuiltInAgent("codex", in: &metadata) {
            AgentMetadata(
                id: "codex",
                name: "Codex",
                description: "Lightweight open-source coding agent by OpenAI",
                iconType: .builtin("openai"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "codex"),
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/codex-acp")
            )
        }

        updateBuiltInAgent("gemini", in: &metadata) {
            AgentMetadata(
                id: "gemini",
                name: "Gemini",
                description: "Open-source AI agent powered by Gemini models",
                iconType: .builtin("gemini"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "gemini"),
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@google/gemini-cli")
            )
        }

        updateBuiltInAgent("kimi", in: &metadata) {
            AgentMetadata(
                id: "kimi",
                name: "Kimi",
                description: "CLI agent powered by Kimi K2, a trillion-parameter MoE model",
                iconType: .builtin("kimi"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "kimi"),
                launchArgs: ["--acp"],
                installMethod: .uv(package: "kimi-cli")
            )
        }

        updateBuiltInAgent("opencode", in: &metadata) {
            AgentMetadata(
                id: "opencode",
                name: "OpenCode",
                description: "Open-source coding agent with multi-session and LSP support",
                iconType: .builtin("opencode"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "opencode"),
                launchArgs: ["acp"],
                installMethod: .npm(package: "opencode-ai@latest")
            )
        }

        updateBuiltInAgent("vibe", in: &metadata) {
            AgentMetadata(
                id: "vibe",
                name: "Vibe",
                description: "Open-source coding assistant powered by Devstral",
                iconType: .builtin("vibe"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "vibe"),
                launchArgs: [],
                installMethod: .uv(package: "mistral-vibe")
            )
        }

        updateBuiltInAgent("qwen", in: &metadata) {
            AgentMetadata(
                id: "qwen",
                name: "Qwen Code",
                description: "CLI tool for agentic coding, powered by Qwen3-Coder",
                iconType: .builtin("qwen"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "qwen"),
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@qwen-code/qwen-code")
            )
        }

        agentMetadata = metadata
    }

    /// Update a built-in agent, always resetting to managed path
    /// Preserves user's enabled state but forces managed path
    private func updateBuiltInAgent(
        _ id: String,
        in metadata: inout [String: AgentMetadata],
        factory: () -> AgentMetadata
    ) {
        let template = factory()
        if var existing = metadata[id] {
            // Preserve enabled state, reset everything else to managed
            existing.executablePath = template.executablePath
            existing.installMethod = template.installMethod
            existing.launchArgs = template.launchArgs
            metadata[id] = existing
        } else {
            metadata[id] = template
        }
    }
}
