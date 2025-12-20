//
//  MCPConfigManager.swift
//  aizen
//
//  Unified config file-based MCP server management for all agents
//

import Foundation

// MARK: - MCP Server Entry (config file format)

struct MCPServerEntry: Codable, Equatable {
    let type: String  // "http", "sse", "stdio"
    let url: String?
    let command: String?
    let args: [String]?
    let env: [String: String]?

    init(type: String, url: String? = nil, command: String? = nil, args: [String]? = nil, env: [String: String]? = nil) {
        self.type = type
        self.url = url
        self.command = command
        self.args = args
        self.env = env
    }

    static func http(url: String) -> MCPServerEntry {
        MCPServerEntry(type: "http", url: url)
    }

    static func sse(url: String) -> MCPServerEntry {
        MCPServerEntry(type: "sse", url: url)
    }

    static func stdio(command: String, args: [String], env: [String: String] = [:]) -> MCPServerEntry {
        MCPServerEntry(type: "stdio", command: command, args: args, env: env.isEmpty ? nil : env)
    }
}

// MARK: - Agent Config Spec

struct AgentMCPConfigSpec {
    let agentId: String
    let configPath: String
    let serverPath: [String]  // JSON path to servers dict
    let format: ConfigFormat

    enum ConfigFormat {
        case json
        case toml
    }

    var expandedPath: String {
        NSString(string: configPath).expandingTildeInPath
    }
}

// MARK: - MCP Config Manager

actor MCPConfigManager {
    static let shared = MCPConfigManager()

    private init() {}

    // MARK: - Agent Config Specs

    private func configSpec(for agentId: String) -> AgentMCPConfigSpec? {
        switch agentId {
        case "claude":
            return AgentMCPConfigSpec(
                agentId: "claude",
                configPath: "~/.claude.json",
                serverPath: ["mcpServers"],  // Global MCP servers
                format: .json
            )
        case "codex":
            return AgentMCPConfigSpec(
                agentId: "codex",
                configPath: "~/.codex/config.json",
                serverPath: ["mcpServers"],
                format: .json
            )
        case "gemini":
            return AgentMCPConfigSpec(
                agentId: "gemini",
                configPath: "~/.gemini/settings.json",
                serverPath: ["mcpServers"],
                format: .json
            )
        case "opencode":
            return AgentMCPConfigSpec(
                agentId: "opencode",
                configPath: "~/.config/opencode/opencode.json",
                serverPath: ["mcp", "servers"],
                format: .json
            )
        case "kimi":
            // Kimi uses runtime --mcp-config-file, create a default location
            return AgentMCPConfigSpec(
                agentId: "kimi",
                configPath: "~/.kimi/mcp.json",
                serverPath: ["mcpServers"],
                format: .json
            )
        default:
            return nil
        }
    }

    // MARK: - Read Servers

    func listServers(agentId: String) -> [String: MCPServerEntry] {
        guard let spec = configSpec(for: agentId) else { return [:] }

        let path = spec.expandedPath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return [:]
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }

            // Navigate to servers location
            var current: Any = json
            for key in spec.serverPath {
                guard let dict = current as? [String: Any],
                      let next = dict[key] else {
                    return [:]
                }
                current = next
            }

            guard let serversDict = current as? [String: [String: Any]] else {
                return [:]
            }

            var servers: [String: MCPServerEntry] = [:]
            for (name, config) in serversDict {
                let type = config["type"] as? String ?? "stdio"
                let url = config["url"] as? String
                let command = config["command"] as? String
                let args = config["args"] as? [String]
                let env = config["env"] as? [String: String]

                servers[name] = MCPServerEntry(
                    type: type,
                    url: url,
                    command: command,
                    args: args,
                    env: env
                )
            }

            return servers
        } catch {
            print("[MCPConfigManager] Failed to parse config for \(agentId): \(error)")
            return [:]
        }
    }

    // MARK: - Add Server

    func addServer(name: String, config: MCPServerEntry, agentId: String) throws {
        guard let spec = configSpec(for: agentId) else {
            throw MCPConfigError.unsupportedAgent(agentId)
        }

        let path = spec.expandedPath
        var json = readOrCreateConfig(at: path)

        // Navigate/create path to servers
        var current = json
        for (index, key) in spec.serverPath.enumerated() {
            if index == spec.serverPath.count - 1 {
                // Last key - this is where servers dict goes
                var servers = current[key] as? [String: Any] ?? [:]
                servers[name] = configToDict(config)
                current[key] = servers
            } else {
                // Intermediate key - ensure it exists
                if current[key] == nil {
                    current[key] = [String: Any]()
                }
                if var nested = current[key] as? [String: Any] {
                    // Continue building path
                    var remaining = Array(spec.serverPath[(index + 1)...])
                    nested = ensurePath(in: nested, path: remaining, finalValue: configToDict(config), serverName: name)
                    current[key] = nested
                    break
                }
            }
        }

        // Rebuild json from current
        json = rebuildJson(original: json, updated: current, path: spec.serverPath, serverName: name, config: config)

        try writeConfig(json, to: path)
    }

    // MARK: - Remove Server

    func removeServer(name: String, agentId: String) throws {
        guard let spec = configSpec(for: agentId) else {
            throw MCPConfigError.unsupportedAgent(agentId)
        }

        let path = spec.expandedPath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPConfigError.configNotFound(path)
        }

        // Navigate to servers and remove
        json = removeFromPath(in: json, path: spec.serverPath, serverName: name)

        try writeConfig(json, to: path)
    }

    // MARK: - Private Helpers

    private func readOrCreateConfig(at path: String) -> [String: Any] {
        if FileManager.default.fileExists(atPath: path),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return [:]
    }

    private func configToDict(_ config: MCPServerEntry) -> [String: Any] {
        var dict: [String: Any] = ["type": config.type]
        if let url = config.url { dict["url"] = url }
        if let command = config.command { dict["command"] = command }
        if let args = config.args { dict["args"] = args }
        if let env = config.env, !env.isEmpty { dict["env"] = env }
        return dict
    }

    private func ensurePath(in dict: [String: Any], path: [String], finalValue: [String: Any], serverName: String) -> [String: Any] {
        guard !path.isEmpty else { return dict }

        var result = dict
        let key = path[0]

        if path.count == 1 {
            // Last key - add server
            var servers = result[key] as? [String: Any] ?? [:]
            servers[serverName] = finalValue
            result[key] = servers
        } else {
            // Intermediate key
            var nested = result[key] as? [String: Any] ?? [:]
            nested = ensurePath(in: nested, path: Array(path.dropFirst()), finalValue: finalValue, serverName: serverName)
            result[key] = nested
        }

        return result
    }

    private func rebuildJson(original: [String: Any], updated: [String: Any], path: [String], serverName: String, config: MCPServerEntry) -> [String: Any] {
        var result = original

        guard !path.isEmpty else { return result }

        let key = path[0]

        if path.count == 1 {
            var servers = result[key] as? [String: Any] ?? [:]
            servers[serverName] = configToDict(config)
            result[key] = servers
        } else {
            var nested = result[key] as? [String: Any] ?? [:]
            nested = rebuildJson(original: nested, updated: [:], path: Array(path.dropFirst()), serverName: serverName, config: config)
            result[key] = nested
        }

        return result
    }

    private func removeFromPath(in dict: [String: Any], path: [String], serverName: String) -> [String: Any] {
        guard !path.isEmpty else { return dict }

        var result = dict
        let key = path[0]

        if path.count == 1 {
            if var servers = result[key] as? [String: Any] {
                servers.removeValue(forKey: serverName)
                result[key] = servers
            }
        } else {
            if var nested = result[key] as? [String: Any] {
                nested = removeFromPath(in: nested, path: Array(path.dropFirst()), serverName: serverName)
                result[key] = nested
            }
        }

        return result
    }

    private func writeConfig(_ json: [String: Any], to path: String) throws {
        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Supported Agents

    func supportsConfigManagement(agentId: String) -> Bool {
        configSpec(for: agentId) != nil
    }
}

// MARK: - Errors

enum MCPConfigError: LocalizedError {
    case unsupportedAgent(String)
    case configNotFound(String)
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAgent(let id):
            return "Agent '\(id)' does not support config-based MCP management"
        case .configNotFound(let path):
            return "Config file not found: \(path)"
        case .invalidConfig(let reason):
            return "Invalid config: \(reason)"
        }
    }
}
