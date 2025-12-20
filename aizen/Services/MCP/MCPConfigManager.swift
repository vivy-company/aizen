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
    let tomlStyle: TOMLStyle

    enum ConfigFormat {
        case json
        case toml
    }

    /// TOML array style for MCP servers
    enum TOMLStyle {
        case none           // JSON format
        case arrayOfTables  // [[mcp_servers]] with name field (Vibe)
        case namedTables    // [mcp_servers.name] (Codex)
    }

    var expandedPath: String {
        NSString(string: configPath).expandingTildeInPath
    }

    init(agentId: String, configPath: String, serverPath: [String], format: ConfigFormat, tomlStyle: TOMLStyle = .none) {
        self.agentId = agentId
        self.configPath = configPath
        self.serverPath = serverPath
        self.format = format
        self.tomlStyle = tomlStyle
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
            // Codex uses TOML with [mcp_servers.<name>] tables
            return AgentMCPConfigSpec(
                agentId: "codex",
                configPath: "~/.codex/config.toml",
                serverPath: ["mcp_servers"],
                format: .toml,
                tomlStyle: .namedTables
            )
        case "gemini":
            return AgentMCPConfigSpec(
                agentId: "gemini",
                configPath: "~/.gemini/settings.json",
                serverPath: ["mcpServers"],
                format: .json
            )
        case "opencode":
            // OpenCode uses mcp directly (not mcp.servers)
            // Format: { "mcp": { "serverName": { "type": "local", "command": [...] } } }
            return AgentMCPConfigSpec(
                agentId: "opencode",
                configPath: "~/.config/opencode/opencode.json",
                serverPath: ["mcp"],
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
        case "vibe":
            // Vibe uses TOML config with [[mcp_servers]] array
            return AgentMCPConfigSpec(
                agentId: "vibe",
                configPath: "~/.vibe/config.toml",
                serverPath: ["mcp_servers"],
                format: .toml,
                tomlStyle: .arrayOfTables
            )
        case "qwen":
            // Qwen uses settings.json with mcpServers (same format as Gemini)
            return AgentMCPConfigSpec(
                agentId: "qwen",
                configPath: "~/.qwen/settings.json",
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

        switch spec.format {
        case .json:
            return listServersJSON(spec: spec)
        case .toml:
            return listServersTOML(spec: spec)
        }
    }

    private func listServersJSON(spec: AgentMCPConfigSpec) -> [String: MCPServerEntry] {
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

                // Handle command - can be string or array (OpenCode uses array)
                var command: String?
                var args: [String]?
                if let cmdString = config["command"] as? String {
                    command = cmdString
                    args = config["args"] as? [String]
                } else if let cmdArray = config["command"] as? [String], !cmdArray.isEmpty {
                    // OpenCode format: command is array like ["npx", "-y", "package"]
                    command = cmdArray[0]
                    args = Array(cmdArray.dropFirst())
                }

                // Handle env - can be "env" or "environment" (OpenCode uses environment)
                let env = (config["env"] as? [String: String]) ?? (config["environment"] as? [String: String])

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
            print("[MCPConfigManager] Failed to parse JSON config: \(error)")
            return [:]
        }
    }

    private func listServersTOML(spec: AgentMCPConfigSpec) -> [String: MCPServerEntry] {
        let path = spec.expandedPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        switch spec.tomlStyle {
        case .arrayOfTables:
            return parseTOMLMCPServersArray(content)
        case .namedTables:
            return parseTOMLMCPServersNamed(content)
        case .none:
            return [:]
        }
    }

    // MARK: - Add Server

    func addServer(name: String, config: MCPServerEntry, agentId: String) throws {
        guard let spec = configSpec(for: agentId) else {
            throw MCPConfigError.unsupportedAgent(agentId)
        }

        switch spec.format {
        case .json:
            try addServerJSON(name: name, config: config, spec: spec)
        case .toml:
            try addServerTOML(name: name, config: config, spec: spec)
        }
    }

    private func addServerJSON(name: String, config: MCPServerEntry, spec: AgentMCPConfigSpec) throws {
        let path = spec.expandedPath
        var json = readOrCreateConfig(at: path)
        let configDict = configToDict(config, agentId: spec.agentId)

        // Navigate/create path to servers
        var current = json
        for (index, key) in spec.serverPath.enumerated() {
            if index == spec.serverPath.count - 1 {
                // Last key - this is where servers dict goes
                var servers = current[key] as? [String: Any] ?? [:]
                servers[name] = configDict
                current[key] = servers
            } else {
                // Intermediate key - ensure it exists
                if current[key] == nil {
                    current[key] = [String: Any]()
                }
                if var nested = current[key] as? [String: Any] {
                    // Continue building path
                    let remaining = Array(spec.serverPath[(index + 1)...])
                    nested = ensurePath(in: nested, path: remaining, finalValue: configDict, serverName: name)
                    current[key] = nested
                    break
                }
            }
        }

        // Rebuild json from current
        json = rebuildJson(original: json, updated: current, path: spec.serverPath, serverName: name, configDict: configDict)

        try writeConfigJSON(json, to: path)
    }

    private func addServerTOML(name: String, config: MCPServerEntry, spec: AgentMCPConfigSpec) throws {
        let path = spec.expandedPath

        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Read existing content or create empty
        var content = ""
        if FileManager.default.fileExists(atPath: path) {
            content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }

        // Remove existing server with same name if present
        content = removeTOMLMCPServer(named: name, from: content, style: spec.tomlStyle)

        // Generate new server entry
        let serverEntry = generateTOMLMCPServer(name: name, config: config, style: spec.tomlStyle)

        // Append to content
        if !content.isEmpty && !content.hasSuffix("\n\n") {
            if content.hasSuffix("\n") {
                content += "\n"
            } else {
                content += "\n\n"
            }
        }
        content += serverEntry

        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Remove Server

    func removeServer(name: String, agentId: String) throws {
        guard let spec = configSpec(for: agentId) else {
            throw MCPConfigError.unsupportedAgent(agentId)
        }

        switch spec.format {
        case .json:
            try removeServerJSON(name: name, spec: spec)
        case .toml:
            try removeServerTOML(name: name, spec: spec)
        }
    }

    private func removeServerJSON(name: String, spec: AgentMCPConfigSpec) throws {
        let path = spec.expandedPath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPConfigError.configNotFound(path)
        }

        // Navigate to servers and remove
        json = removeFromPath(in: json, path: spec.serverPath, serverName: name)

        try writeConfigJSON(json, to: path)
    }

    private func removeServerTOML(name: String, spec: AgentMCPConfigSpec) throws {
        let path = spec.expandedPath
        guard FileManager.default.fileExists(atPath: path),
              var content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw MCPConfigError.configNotFound(path)
        }

        content = removeTOMLMCPServer(named: name, from: content, style: spec.tomlStyle)

        try content.write(toFile: path, atomically: true, encoding: .utf8)
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

    private func configToDict(_ config: MCPServerEntry, agentId: String) -> [String: Any] {
        // OpenCode uses different format
        if agentId == "opencode" {
            return configToDictOpenCode(config)
        }
        return configToDictStandard(config)
    }

    private func configToDictStandard(_ config: MCPServerEntry) -> [String: Any] {
        var dict: [String: Any] = ["type": config.type]
        if let url = config.url { dict["url"] = url }
        if let command = config.command { dict["command"] = command }
        if let args = config.args { dict["args"] = args }
        if let env = config.env, !env.isEmpty { dict["env"] = env }
        return dict
    }

    /// OpenCode format: command is array, env is "environment", type is "local"/"remote"
    private func configToDictOpenCode(_ config: MCPServerEntry) -> [String: Any] {
        var dict: [String: Any] = [:]

        // OpenCode uses "local" for stdio, "remote" for http/sse
        if config.type == "stdio" {
            dict["type"] = "local"
        } else {
            dict["type"] = "remote"
        }

        if let url = config.url {
            dict["url"] = url
        }

        // OpenCode uses command as array: ["npx", "-y", "package"]
        if let command = config.command {
            var cmdArray = [command]
            if let args = config.args {
                cmdArray.append(contentsOf: args)
            }
            dict["command"] = cmdArray
        }

        if let env = config.env, !env.isEmpty {
            dict["environment"] = env
        }

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

    private func rebuildJson(original: [String: Any], updated: [String: Any], path: [String], serverName: String, configDict: [String: Any]) -> [String: Any] {
        var result = original

        guard !path.isEmpty else { return result }

        let key = path[0]

        if path.count == 1 {
            var servers = result[key] as? [String: Any] ?? [:]
            servers[serverName] = configDict
            result[key] = servers
        } else {
            var nested = result[key] as? [String: Any] ?? [:]
            nested = rebuildJson(original: nested, updated: [:], path: Array(path.dropFirst()), serverName: serverName, configDict: configDict)
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

    private func writeConfigJSON(_ json: [String: Any], to path: String) throws {
        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - TOML Helpers

    /// Parse MCP servers from Vibe's TOML config format (array of tables)
    /// Vibe uses [[mcp_servers]] array with name, transport, url, command, args fields
    private func parseTOMLMCPServersArray(_ content: String) -> [String: MCPServerEntry] {
        var servers: [String: MCPServerEntry] = [:]
        let lines = content.components(separatedBy: .newlines)

        var currentServer: [String: Any]?
        var inMCPServer = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Start of new mcp_servers entry
            if trimmed == "[[mcp_servers]]" {
                // Save previous server if exists
                if let server = currentServer, let name = server["name"] as? String {
                    let transport = mapVibeTransport(server["transport"] as? String ?? "stdio")
                    servers[name] = MCPServerEntry(
                        type: transport,
                        url: server["url"] as? String,
                        command: server["command"] as? String,
                        args: server["args"] as? [String],
                        env: nil
                    )
                }
                currentServer = [:]
                inMCPServer = true
                continue
            }

            // End of mcp_servers section (new section started)
            if trimmed.hasPrefix("[") && trimmed != "[[mcp_servers]]" {
                if let server = currentServer, let name = server["name"] as? String {
                    let transport = mapVibeTransport(server["transport"] as? String ?? "stdio")
                    servers[name] = MCPServerEntry(
                        type: transport,
                        url: server["url"] as? String,
                        command: server["command"] as? String,
                        args: server["args"] as? [String],
                        env: nil
                    )
                }
                currentServer = nil
                inMCPServer = false
                continue
            }

            // Parse key-value pairs within mcp_servers
            if inMCPServer, let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)

                // Parse string value
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                    currentServer?[key] = value
                }
                // Parse array value
                else if value.hasPrefix("[") && value.hasSuffix("]") {
                    let arrayContent = String(value.dropFirst().dropLast())
                    let items = arrayContent.components(separatedBy: ",").compactMap { item -> String? in
                        let trimmedItem = item.trimmingCharacters(in: .whitespaces)
                        if trimmedItem.hasPrefix("\"") && trimmedItem.hasSuffix("\"") {
                            return String(trimmedItem.dropFirst().dropLast())
                        }
                        return nil
                    }
                    currentServer?[key] = items
                }
            }
        }

        // Save last server
        if let server = currentServer, let name = server["name"] as? String {
            let transport = mapVibeTransport(server["transport"] as? String ?? "stdio")
            servers[name] = MCPServerEntry(
                type: transport,
                url: server["url"] as? String,
                command: server["command"] as? String,
                args: server["args"] as? [String],
                env: nil
            )
        }

        return servers
    }

    /// Map Vibe transport names to internal type names
    private func mapVibeTransport(_ transport: String) -> String {
        switch transport {
        case "streamable-http":
            return "sse"
        default:
            return transport
        }
    }

    /// Parse MCP servers from Codex's TOML config format (named tables)
    /// Codex uses [mcp_servers.name] tables with command, args, env fields
    private func parseTOMLMCPServersNamed(_ content: String) -> [String: MCPServerEntry] {
        var servers: [String: MCPServerEntry] = [:]
        let lines = content.components(separatedBy: .newlines)

        var currentServerName: String?
        var currentServer: [String: Any]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for [mcp_servers.name] pattern
            if trimmed.hasPrefix("[mcp_servers.") && trimmed.hasSuffix("]") && !trimmed.hasPrefix("[[") {
                // Save previous server if exists
                if let name = currentServerName, let server = currentServer {
                    servers[name] = MCPServerEntry(
                        type: "stdio",
                        url: server["url"] as? String,
                        command: server["command"] as? String,
                        args: server["args"] as? [String],
                        env: server["env"] as? [String: String]
                    )
                }

                // Extract server name
                let startIdx = trimmed.index(trimmed.startIndex, offsetBy: 13) // "[mcp_servers."
                let endIdx = trimmed.index(before: trimmed.endIndex) // "]"
                currentServerName = String(trimmed[startIdx..<endIdx])
                currentServer = [:]
                continue
            }

            // New section that's not mcp_servers
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[mcp_servers") {
                if let name = currentServerName, let server = currentServer {
                    servers[name] = MCPServerEntry(
                        type: "stdio",
                        url: server["url"] as? String,
                        command: server["command"] as? String,
                        args: server["args"] as? [String],
                        env: server["env"] as? [String: String]
                    )
                }
                currentServerName = nil
                currentServer = nil
                continue
            }

            // Parse key-value pairs
            if currentServer != nil, let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)

                // Parse string value
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    currentServer?[key] = String(value.dropFirst().dropLast())
                }
                // Parse array value
                else if value.hasPrefix("[") && value.hasSuffix("]") {
                    let arrayContent = String(value.dropFirst().dropLast())
                    let items = arrayContent.components(separatedBy: ",").compactMap { item -> String? in
                        let trimmedItem = item.trimmingCharacters(in: .whitespaces)
                        if trimmedItem.hasPrefix("\"") && trimmedItem.hasSuffix("\"") {
                            return String(trimmedItem.dropFirst().dropLast())
                        }
                        return nil
                    }
                    currentServer?[key] = items
                }
            }
        }

        // Save last server
        if let name = currentServerName, let server = currentServer {
            servers[name] = MCPServerEntry(
                type: "stdio",
                url: server["url"] as? String,
                command: server["command"] as? String,
                args: server["args"] as? [String],
                env: server["env"] as? [String: String]
            )
        }

        return servers
    }

    /// Generate TOML entry for an MCP server
    private func generateTOMLMCPServer(name: String, config: MCPServerEntry, style: AgentMCPConfigSpec.TOMLStyle) -> String {
        switch style {
        case .arrayOfTables:
            return generateTOMLMCPServerArray(name: name, config: config)
        case .namedTables:
            return generateTOMLMCPServerNamed(name: name, config: config)
        case .none:
            return ""
        }
    }

    /// Generate Vibe-style TOML entry [[mcp_servers]]
    private func generateTOMLMCPServerArray(name: String, config: MCPServerEntry) -> String {
        var lines: [String] = ["[[mcp_servers]]"]
        lines.append("name = \"\(name)\"")

        // Map internal type to Vibe's transport names
        let transport: String
        switch config.type {
        case "sse":
            transport = "streamable-http"
        default:
            transport = config.type
        }
        lines.append("transport = \"\(transport)\"")

        if let url = config.url {
            lines.append("url = \"\(url)\"")
        }
        if let command = config.command {
            lines.append("command = \"\(command)\"")
        }
        if let args = config.args, !args.isEmpty {
            let argsStr = args.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("args = [\(argsStr)]")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Generate Codex-style TOML entry [mcp_servers.name]
    private func generateTOMLMCPServerNamed(name: String, config: MCPServerEntry) -> String {
        var lines: [String] = ["[mcp_servers.\(name)]"]

        if let command = config.command {
            lines.append("command = \"\(command)\"")
        }
        if let args = config.args, !args.isEmpty {
            let argsStr = args.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("args = [\(argsStr)]")
        }
        if let url = config.url {
            lines.append("url = \"\(url)\"")
        }
        if let env = config.env, !env.isEmpty {
            let envStr = env.map { "\"\($0.key)\" = \"\($0.value)\"" }.joined(separator: ", ")
            lines.append("env = { \(envStr) }")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Remove an MCP server entry from TOML content by name
    private func removeTOMLMCPServer(named name: String, from content: String, style: AgentMCPConfigSpec.TOMLStyle) -> String {
        switch style {
        case .arrayOfTables:
            return removeTOMLMCPServerArray(named: name, from: content)
        case .namedTables:
            return removeTOMLMCPServerNamed(named: name, from: content)
        case .none:
            return content
        }
    }

    /// Remove Vibe-style [[mcp_servers]] entry
    private func removeTOMLMCPServerArray(named name: String, from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var skipUntilNextSection = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Start of new mcp_servers entry
            if trimmed == "[[mcp_servers]]" {
                // Check next few lines for the name
                var currentServerName: String?
                for lookAhead in (index + 1)..<min(index + 10, lines.count) {
                    let nextLine = lines[lookAhead].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("name") && nextLine.contains("=") {
                        if let equalIdx = nextLine.firstIndex(of: "=") {
                            var value = String(nextLine[nextLine.index(after: equalIdx)...])
                                .trimmingCharacters(in: .whitespaces)
                            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                                value = String(value.dropFirst().dropLast())
                            }
                            currentServerName = value
                        }
                        break
                    }
                    if nextLine.hasPrefix("[") {
                        break
                    }
                }

                if currentServerName == name {
                    skipUntilNextSection = true
                    continue
                } else {
                    skipUntilNextSection = false
                }
            }

            // New section (not mcp_servers array entry) stops skipping
            if trimmed.hasPrefix("[") && trimmed != "[[mcp_servers]]" {
                skipUntilNextSection = false
            }

            if !skipUntilNextSection {
                result.append(line)
            }
        }

        return cleanupTOMLEmptyLines(result)
    }

    /// Remove Codex-style [mcp_servers.name] entry
    private func removeTOMLMCPServerNamed(named name: String, from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var skipUntilNextSection = false
        let targetSection = "[mcp_servers.\(name)]"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check if this is the section to remove
            if trimmed == targetSection {
                skipUntilNextSection = true
                continue
            }

            // Any new section stops skipping
            if trimmed.hasPrefix("[") && skipUntilNextSection {
                skipUntilNextSection = false
            }

            if !skipUntilNextSection {
                result.append(line)
            }
        }

        return cleanupTOMLEmptyLines(result)
    }

    private func cleanupTOMLEmptyLines(_ lines: [String]) -> String {
        var cleaned: [String] = []
        var lastWasEmpty = false
        for line in lines {
            let isEmpty = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isEmpty && lastWasEmpty {
                continue
            }
            cleaned.append(line)
            lastWasEmpty = isEmpty
        }
        return cleaned.joined(separator: "\n")
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
