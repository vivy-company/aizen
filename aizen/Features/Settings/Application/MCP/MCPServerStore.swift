//
//  MCPServerStore.swift
//  aizen
//
//  Aizen-managed MCP server store for ACP sessions.
//

import Foundation

// MARK: - MCP Definitions

nonisolated enum MCPTransportKind: String, Codable, Equatable, Sendable {
    case stdio
    case http
    case sse
    case acp
}

nonisolated struct MCPServerDefinition: Codable, Equatable, Sendable {
    let transport: MCPTransportKind
    let url: String?
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let headers: [MCPHeaderDefinition]?

    init(
        transport: MCPTransportKind,
        url: String? = nil,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        headers: [MCPHeaderDefinition]? = nil
    ) {
        self.transport = transport
        self.url = url
        self.command = command
        self.args = args
        self.env = env
        self.headers = headers
    }

    static func http(url: String, headers: [MCPHeaderDefinition] = []) -> MCPServerDefinition {
        MCPServerDefinition(transport: .http, url: url, headers: headers.isEmpty ? nil : headers)
    }

    static func sse(url: String, headers: [MCPHeaderDefinition] = []) -> MCPServerDefinition {
        MCPServerDefinition(transport: .sse, url: url, headers: headers.isEmpty ? nil : headers)
    }

    static func stdio(command: String, args: [String], env: [String: String] = [:]) -> MCPServerDefinition {
        MCPServerDefinition(
            transport: .stdio,
            command: command,
            args: args,
            env: env.isEmpty ? nil : env
        )
    }

    static func acp(name: String, headers: [MCPHeaderDefinition] = []) -> MCPServerDefinition {
        MCPServerDefinition(
            transport: .acp,
            command: name,
            headers: headers.isEmpty ? nil : headers
        )
    }
}

nonisolated struct MCPHeaderDefinition: Codable, Equatable, Sendable {
    let name: String
    let value: String
}

nonisolated struct MCPServerStoreSnapshot: Codable, Sendable {
    var agentDefaults: [String: [String: MCPServerDefinition]]
    var sessionOverrides: [String: [String: MCPServerDefinition]]

    static let empty = MCPServerStoreSnapshot(agentDefaults: [:], sessionOverrides: [:])
}

// MARK: - MCP Server Store

actor MCPServerStore {
    static let shared = MCPServerStore()

    private let defaults: UserDefaults
    private let storageKey = "aizen.mcp.sessionStore.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Private Helpers

    func loadSnapshot() -> MCPServerStoreSnapshot {
        guard let data = defaults.data(forKey: storageKey) else {
            return .empty
        }

        do {
            return try decoder.decode(MCPServerStoreSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }

    func saveSnapshot(_ snapshot: MCPServerStoreSnapshot) throws {
        let data = try encoder.encode(snapshot)
        defaults.set(data, forKey: storageKey)
    }
}
