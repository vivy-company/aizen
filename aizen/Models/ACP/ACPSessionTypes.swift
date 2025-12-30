//
//  ACPSessionTypes.swift
//  aizen
//
//  Agent Client Protocol - Core Session Types
//

import Foundation

// MARK: - Session ID

nonisolated struct SessionId: Codable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Client & Agent Info

nonisolated struct ClientInfo: Codable {
    let name: String
    let title: String?
    let version: String?
}

nonisolated struct AgentInfo: Codable {
    let name: String
    let version: String
}

// MARK: - Stop Reason

nonisolated enum StopReason: String, Codable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case maxTurnRequests = "max_turn_requests"
    case refusal = "refusal"
    case cancelled = "cancelled"
}

// MARK: - Session Mode Types

nonisolated enum SessionMode: String, Codable {
    case code
    case chat
    case ask
}

nonisolated struct ModeInfo: Codable, Hashable {
    let id: String
    let name: String
    let description: String?
}

nonisolated struct ModesInfo: Codable {
    let currentModeId: String
    let availableModes: [ModeInfo]

    enum CodingKeys: String, CodingKey {
        case currentModeId = "currentModeId"
        case availableModes = "availableModes"
    }
}

// MARK: - Model Selection Types

nonisolated struct ModelInfo: Codable, Hashable {
    let modelId: String
    let name: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "modelId"
        case name
        case description
    }
}

nonisolated struct ModelsInfo: Codable {
    let currentModelId: String
    let availableModels: [ModelInfo]

    enum CodingKeys: String, CodingKey {
        case currentModelId = "currentModelId"
        case availableModels = "availableModels"
    }
}

// MARK: - Authentication Types

nonisolated struct AuthMethod: Codable {
    let id: String
    let name: String
    let description: String?
}

// MARK: - MCP Server Configuration

nonisolated enum MCPServerConfig: Codable {
    case stdio(StdioServerConfig)
    case http(HTTPServerConfig)
    case sse(SSEServerConfig)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "stdio":
            self = .stdio(try StdioServerConfig(from: decoder))
        case "http":
            self = .http(try HTTPServerConfig(from: decoder))
        case "sse":
            self = .sse(try SSEServerConfig(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown MCP server type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .stdio(let config):
            try container.encode("stdio", forKey: .type)
            try config.encode(to: encoder)
        case .http(let config):
            try container.encode("http", forKey: .type)
            try config.encode(to: encoder)
        case .sse(let config):
            try container.encode("sse", forKey: .type)
            try config.encode(to: encoder)
        }
    }
}

nonisolated struct StdioServerConfig: Codable {
    let name: String
    let command: String
    let args: [String]
    let env: [EnvVariable]
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, command, args, env, _meta
    }
}

nonisolated struct HTTPServerConfig: Codable {
    let name: String
    let url: String
    let headers: [HTTPHeader]?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, url, headers, _meta
    }
}

nonisolated struct SSEServerConfig: Codable {
    let name: String
    let url: String
    let headers: [HTTPHeader]?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, url, headers, _meta
    }
}

nonisolated struct HTTPHeader: Codable {
    let name: String
    let value: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, value, _meta
    }
}
