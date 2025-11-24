//
//  ACPSessionTypes.swift
//  aizen
//
//  Agent Client Protocol - Session, Mode, Model, and Request/Response Types
//

import Foundation

// MARK: - ACP Protocol Types

struct SessionId: Codable, Hashable {
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

// MARK: - Capabilities

struct ClientCapabilities: Codable {
    let fs: FileSystemCapabilities
    let terminal: Bool

    enum CodingKeys: String, CodingKey {
        case fs
        case terminal
    }
}

struct FileSystemCapabilities: Codable {
    let readTextFile: Bool
    let writeTextFile: Bool

    enum CodingKeys: String, CodingKey {
        case readTextFile
        case writeTextFile
    }
}

struct AgentCapabilities: Codable {
    let loadSession: Bool?
    let mcpCapabilities: MCPCapabilities?

    enum CodingKeys: String, CodingKey {
        case loadSession = "load_session"
        case mcpCapabilities = "mcp_capabilities"
    }
}

struct MCPCapabilities: Codable {
    let http: Bool?
    let ssh: Bool?
}

// MARK: - Request/Response Types

struct InitializeRequest: Codable {
    let protocolVersion: Int
    let clientCapabilities: ClientCapabilities

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case clientCapabilities
    }
}

struct InitializeResponse: Codable {
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

struct AgentInfo: Codable {
    let name: String
    let version: String
}

struct NewSessionRequest: Codable {
    let cwd: String
    let mcpServers: [MCPServerConfig]

    enum CodingKeys: String, CodingKey {
        case cwd
        case mcpServers
    }
}

struct MCPServerConfig: Codable {
    let name: String
    let command: String
    let args: [String]?
    let env: [String: String]?
}

struct NewSessionResponse: Codable {
    let sessionId: SessionId
    let modes: ModesInfo?
    let models: ModelsInfo?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modes
        case models
    }
}

struct LoadSessionRequest: Codable {
    let sessionId: SessionId
    let cwd: String?
    let mcpServers: [MCPServerConfig]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case cwd
        case mcpServers
    }
}

struct LoadSessionResponse: Codable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

struct CancelSessionRequest: Codable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

struct SessionPromptRequest: Codable {
    let sessionId: SessionId
    let prompt: [ContentBlock]

    enum CodingKeys: String, CodingKey {
        case sessionId
        case prompt
    }
}

struct SessionPromptResponse: Codable {
    let stopReason: StopReason

    enum CodingKeys: String, CodingKey {
        case stopReason
    }
}

enum StopReason: String, Codable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case maxTurnRequests = "max_turn_requests"
    case refusal = "refusal"
    case cancelled = "cancelled"
}

// MARK: - Session Mode Types

enum SessionMode: String, Codable {
    case code
    case chat
    case ask
}

struct ModeInfo: Codable, Hashable {
    let id: String
    let name: String
    let description: String?
}

struct ModesInfo: Codable {
    let currentModeId: String
    let availableModes: [ModeInfo]

    enum CodingKeys: String, CodingKey {
        case currentModeId = "currentModeId"
        case availableModes = "availableModes"
    }
}

struct SetModeRequest: Codable {
    let sessionId: SessionId
    let modeId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modeId
    }
}

struct SetModeResponse: Codable {
    let success: Bool
}

// MARK: - Model Selection Types

struct ModelInfo: Codable, Hashable {
    let modelId: String
    let name: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "modelId"
        case name
        case description
    }
}

struct ModelsInfo: Codable {
    let currentModelId: String
    let availableModels: [ModelInfo]

    enum CodingKeys: String, CodingKey {
        case currentModelId = "currentModelId"
        case availableModels = "availableModels"
    }
}

struct SetModelRequest: Codable {
    let sessionId: SessionId
    let modelId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modelId
    }
}

struct SetModelResponse: Codable {
    let success: Bool
}

// MARK: - Authentication Types

struct AuthMethod: Codable {
    let id: String
    let name: String
    let description: String?
}

struct AuthenticateRequest: Codable {
    let methodId: String
    let credentials: [String: String]?

    enum CodingKeys: String, CodingKey {
        case methodId
        case credentials
    }
}

struct AuthenticateResponse: Codable {
    let success: Bool
    let error: String?
}

// MARK: - File System Types

struct ReadTextFileRequest: Codable {
    let path: String
    let startLine: Int?
    let endLine: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case startLine = "start_line"
        case endLine = "end_line"
    }
}

struct ReadTextFileResponse: Codable {
    let content: String
    let totalLines: Int

    enum CodingKeys: String, CodingKey {
        case content
        case totalLines = "total_lines"
    }
}

struct WriteTextFileRequest: Codable {
    let path: String
    let content: String
}

struct WriteTextFileResponse: Codable {
    let success: Bool
}

// MARK: - Permission Types

struct RequestPermissionRequest: Codable {
    let message: String?
    let options: [PermissionOption]?
    let sessionId: SessionId?
    let toolCall: PermissionToolCall?

    enum CodingKeys: String, CodingKey {
        case message
        case options
        case sessionId
        case toolCall
    }
}

struct PermissionOption: Codable {
    let kind: String
    let name: String
    let optionId: String

    enum CodingKeys: String, CodingKey {
        case kind
        case name
        case optionId
    }
}

struct PermissionToolCall: Codable {
    let toolCallId: String
    let rawInput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case rawInput
    }
}

enum PermissionDecision: String, Codable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

struct RequestPermissionResponse: Codable {
    let outcome: PermissionOutcome

    enum CodingKeys: String, CodingKey {
        case outcome
    }
}

struct PermissionOutcome: Codable {
    let outcome: String // "selected" or "cancelled"
    let optionId: String?

    enum CodingKeys: String, CodingKey {
        case outcome
        case optionId
    }

    init(optionId: String) {
        self.outcome = "selected"
        self.optionId = optionId
    }

    init(cancelled: Bool) {
        self.outcome = "cancelled"
        self.optionId = nil
    }
}

// MARK: - Session Update Types

enum SessionUpdateType: String, Codable {
    case userMessageChunk = "user_message_chunk"
    case agentMessageChunk = "agent_message_chunk"
    case agentThoughtChunk = "agent_thought_chunk"
    case toolCall = "tool_call"
    case toolCallUpdate = "tool_call_update"
    case plan = "plan"
    case availableCommandsUpdate = "available_commands_update"
    case currentModeUpdate = "current_mode_update"
}

struct SessionUpdateNotification: Codable {
    let sessionId: SessionId
    let update: SessionUpdate

    enum CodingKeys: String, CodingKey {
        case sessionId
        case update
    }
}

struct SessionUpdate: Codable {
    let sessionUpdate: String
    let content: AnyCodable? // Can be ContentBlock or array depending on update type
    let toolCalls: [ToolCall]?
    let plan: Plan?
    let availableCommands: [AvailableCommand]?
    let currentMode: SessionMode?

    // Individual tool call fields (when sessionUpdate is "tool_call" or "tool_call_update")
    let toolCallId: String?
    let title: String?
    let kind: ToolKind?
    let status: ToolStatus?
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case sessionUpdate
        case content
        case toolCalls
        case plan
        case availableCommands
        case currentMode
        case toolCallId
        case title
        case kind
        case status
        case locations
        case rawInput
        case rawOutput
    }
}
