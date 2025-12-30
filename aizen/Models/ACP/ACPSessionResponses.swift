//
//  ACPSessionResponses.swift
//  aizen
//
//  Agent Client Protocol - Response Types
//

import Foundation

// MARK: - Initialize

nonisolated struct InitializeResponse: Codable {
    let protocolVersion: Int
    let agentInfo: AgentInfo?
    let agentCapabilities: AgentCapabilities
    let authMethods: [AuthMethod]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case agentInfo
        case agentCapabilities
        case authMethods
    }
}

// MARK: - Session Management

nonisolated struct NewSessionResponse: Codable {
    let sessionId: SessionId
    // Legacy API (backward compatibility)
    let modes: ModesInfo?
    let models: ModelsInfo?
    // New API (takes precedence over modes/models)
    let configOptions: [SessionConfigOption]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modes
        case models
        case configOptions
    }
}

nonisolated struct LoadSessionResponse: Codable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

// MARK: - Prompt

nonisolated struct SessionPromptResponse: Codable {
    let stopReason: StopReason

    enum CodingKeys: String, CodingKey {
        case stopReason
    }
}

// MARK: - Mode & Model Selection

nonisolated struct SetModeResponse: Codable {
    let success: Bool
}

nonisolated struct SetModelResponse: Codable {
    let success: Bool
}

nonisolated struct SetSessionConfigOptionResponse: Codable {
    let configOptions: [SessionConfigOption]

    enum CodingKeys: String, CodingKey {
        case configOptions
    }
}

// MARK: - Authentication

nonisolated struct AuthenticateResponse: Codable {
    let success: Bool
    let error: String?
}

// MARK: - File System

nonisolated struct ReadTextFileResponse: Codable {
    let content: String
    let totalLines: Int?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content
        case totalLines = "total_lines"
        case _meta
    }
}

nonisolated struct WriteTextFileResponse: Codable {
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case _meta
    }
}
