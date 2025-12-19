//
//  AgentConfigSpec.swift
//  aizen
//
//  Configuration specification for agent rules and settings
//

import Foundation

// MARK: - Agent Command

struct AgentCommand: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String

    var content: String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    init(name: String, path: String) {
        self.id = path
        self.name = name
        self.path = path
    }
}

// MARK: - Config File Type

enum AgentConfigFileType: String, Codable {
    case markdown  // CLAUDE.md, AGENTS.md, GEMINI.md
    case toml      // config.toml
    case json      // settings.json, opencode.json
}

// MARK: - Config File Spec

struct AgentConfigFile: Codable, Identifiable {
    let id: String
    let name: String
    let path: String
    let type: AgentConfigFileType
    let isRulesFile: Bool
    let description: String?

    var expandedPath: String {
        NSString(string: path).expandingTildeInPath
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: expandedPath)
    }

    init(
        id: String,
        name: String,
        path: String,
        type: AgentConfigFileType,
        isRulesFile: Bool = false,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.isRulesFile = isRulesFile
        self.description = description
    }
}

// MARK: - Agent Config Spec

struct AgentConfigSpec {
    let agentId: String
    let configFiles: [AgentConfigFile]
    let commandsDirectory: String?

    var rulesFile: AgentConfigFile? {
        configFiles.first { $0.isRulesFile }
    }

    var settingsFiles: [AgentConfigFile] {
        configFiles.filter { !$0.isRulesFile }
    }

    var expandedCommandsDirectory: String? {
        guard let dir = commandsDirectory else { return nil }
        return NSString(string: dir).expandingTildeInPath
    }
}

// MARK: - Agent Config Registry

enum AgentConfigRegistry {
    static func spec(for agentId: String) -> AgentConfigSpec {
        switch agentId {
        case "claude":
            return AgentConfigSpec(
                agentId: "claude",
                configFiles: [
                    AgentConfigFile(
                        id: "claude-rules",
                        name: "Global Rules",
                        path: "~/.claude/CLAUDE.md",
                        type: .markdown,
                        isRulesFile: true,
                        description: "Instructions that apply to all Claude Code sessions"
                    ),
                    AgentConfigFile(
                        id: "claude-settings",
                        name: "Settings",
                        path: "~/.claude/settings.json",
                        type: .json,
                        description: "Claude Code settings and permissions"
                    )
                ],
                commandsDirectory: "~/.claude/commands"
            )

        case "codex":
            return AgentConfigSpec(
                agentId: "codex",
                configFiles: [
                    AgentConfigFile(
                        id: "codex-rules",
                        name: "Instructions",
                        path: "~/.codex/instructions.md",
                        type: .markdown,
                        isRulesFile: true,
                        description: "Instructions that apply to all Codex sessions"
                    ),
                    AgentConfigFile(
                        id: "codex-config",
                        name: "Configuration",
                        path: "~/.codex/config.toml",
                        type: .toml,
                        description: "Codex settings and preferences"
                    )
                ],
                commandsDirectory: nil
            )

        case "gemini":
            return AgentConfigSpec(
                agentId: "gemini",
                configFiles: [
                    AgentConfigFile(
                        id: "gemini-rules",
                        name: "Global Rules",
                        path: "~/.gemini/GEMINI.md",
                        type: .markdown,
                        isRulesFile: true,
                        description: "Instructions that apply to all Gemini sessions"
                    ),
                    AgentConfigFile(
                        id: "gemini-settings",
                        name: "Settings",
                        path: "~/.gemini/settings.json",
                        type: .json,
                        description: "Gemini settings and preferences"
                    )
                ],
                commandsDirectory: nil
            )

        case "kimi":
            return AgentConfigSpec(
                agentId: "kimi",
                configFiles: [],
                commandsDirectory: nil
            )

        case "opencode":
            return AgentConfigSpec(
                agentId: "opencode",
                configFiles: [
                    AgentConfigFile(
                        id: "opencode-rules",
                        name: "Global Rules",
                        path: "~/.config/opencode/AGENTS.md",
                        type: .markdown,
                        isRulesFile: true,
                        description: "Instructions that apply to all OpenCode sessions"
                    ),
                    AgentConfigFile(
                        id: "opencode-config",
                        name: "Configuration",
                        path: "~/.config/opencode/opencode.json",
                        type: .json,
                        description: "OpenCode settings and preferences"
                    )
                ],
                commandsDirectory: nil
            )

        default:
            return AgentConfigSpec(
                agentId: agentId,
                configFiles: [],
                commandsDirectory: nil
            )
        }
    }

    static var supportedAgents: [String] {
        ["claude", "codex", "gemini", "opencode"]
    }
}
