//
//  ACPSessionRequests.swift
//  aizen
//
//  Agent Client Protocol - Request Types
//

import Foundation

// MARK: - Initialize

nonisolated struct InitializeRequest: Codable {
    let protocolVersion: Int
    let clientCapabilities: ClientCapabilities
    let clientInfo: ClientInfo?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case clientCapabilities
        case clientInfo
    }
}

// MARK: - Session Management

nonisolated struct NewSessionRequest: Codable {
    let cwd: String
    let mcpServers: [MCPServerConfig]

    enum CodingKeys: String, CodingKey {
        case cwd
        case mcpServers
    }
}

nonisolated struct LoadSessionRequest: Codable {
    let sessionId: SessionId
    let cwd: String?
    let mcpServers: [MCPServerConfig]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case cwd
        case mcpServers
    }
}

nonisolated struct CancelSessionRequest: Codable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

// MARK: - Prompt

nonisolated struct SessionPromptRequest: Codable {
    let sessionId: SessionId
    let prompt: [ContentBlock]

    enum CodingKeys: String, CodingKey {
        case sessionId
        case prompt
    }
}

// MARK: - Mode & Model Selection

nonisolated struct SetModeRequest: Codable {
    let sessionId: SessionId
    let modeId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modeId
    }
}

nonisolated struct SetModelRequest: Codable {
    let sessionId: SessionId
    let modelId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modelId
    }
}

nonisolated struct SetSessionConfigOptionRequest: Codable {
    let sessionId: SessionId
    let configId: SessionConfigId
    let value: SessionConfigValueId

    enum CodingKeys: String, CodingKey {
        case sessionId
        case configId
        case value
    }
}

// MARK: - Authentication

nonisolated struct AuthenticateRequest: Codable {
    let methodId: String
    let credentials: [String: String]?

    enum CodingKeys: String, CodingKey {
        case methodId
        case credentials
    }
}

// MARK: - File System

nonisolated struct ReadTextFileRequest: Codable {
    let path: String
    let line: Int?  // Start line (1-based per ACP spec)
    let limit: Int?  // Number of lines to read
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, limit, sessionId, _meta
    }
}

nonisolated struct WriteTextFileRequest: Codable {
    let path: String
    let content: String
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, content, sessionId, _meta
    }
}
