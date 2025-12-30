//
//  ACPSessionUpdate.swift
//  aizen
//
//  Agent Client Protocol - Session Update Types
//

import Foundation

// MARK: - Session Update Notification

nonisolated struct SessionUpdateNotification: Codable {
    let sessionId: SessionId
    let update: SessionUpdate
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId, update, _meta
    }
}

// MARK: - Session Update

nonisolated enum SessionUpdate: Codable {
    case userMessageChunk(ContentBlock)
    case agentMessageChunk(ContentBlock)
    case agentThoughtChunk(ContentBlock)
    case toolCall(ToolCallUpdate)
    case toolCallUpdate(ToolCallUpdateDetails)
    case plan(Plan)
    case availableCommandsUpdate([AvailableCommand])
    case currentModeUpdate(String)
    case configOptionUpdate([SessionConfigOption])

    enum CodingKeys: String, CodingKey {
        case sessionUpdate
        case content  // For ContentChunk types (user/agent/thought message chunks)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let updateType = try container.decode(String.self, forKey: .sessionUpdate)

        switch updateType {
        case "user_message_chunk":
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .userMessageChunk(content)
        case "agent_message_chunk":
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .agentMessageChunk(content)
        case "agent_thought_chunk":
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .agentThoughtChunk(content)
        case "tool_call":
            let toolCall = try ToolCallUpdate(from: decoder)
            self = .toolCall(toolCall)
        case "tool_call_update":
            let details = try ToolCallUpdateDetails(from: decoder)
            self = .toolCallUpdate(details)
        case "plan":
            let plan = try Plan(from: decoder)
            self = .plan(plan)
        case "available_commands_update":
            let commands = try decoder.container(keyedBy: AnyCodingKey.self).decode([AvailableCommand].self, forKey: AnyCodingKey(stringValue: "availableCommands")!)
            self = .availableCommandsUpdate(commands)
        case "current_mode_update":
            let modeId = try decoder.container(keyedBy: AnyCodingKey.self).decode(String.self, forKey: AnyCodingKey(stringValue: "currentModeId")!)
            self = .currentModeUpdate(modeId)
        case "config_option_update":
            let configOptions = try decoder.container(keyedBy: AnyCodingKey.self).decode([SessionConfigOption].self, forKey: AnyCodingKey(stringValue: "configOptions")!)
            self = .configOptionUpdate(configOptions)
        default:
            throw DecodingError.dataCorruptedError(forKey: .sessionUpdate, in: container, debugDescription: "Unknown session update type: \(updateType)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .userMessageChunk(let content):
            try container.encode("user_message_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .agentMessageChunk(let content):
            try container.encode("agent_message_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .agentThoughtChunk(let content):
            try container.encode("agent_thought_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .toolCall(let toolCall):
            try container.encode("tool_call", forKey: .sessionUpdate)
            try toolCall.encode(to: encoder)
        case .toolCallUpdate(let details):
            try container.encode("tool_call_update", forKey: .sessionUpdate)
            try details.encode(to: encoder)
        case .plan(let plan):
            try container.encode("plan", forKey: .sessionUpdate)
            try plan.encode(to: encoder)
        case .availableCommandsUpdate(let commands):
            try container.encode("available_commands_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(commands, forKey: AnyCodingKey(stringValue: "availableCommands")!)
        case .currentModeUpdate(let modeId):
            try container.encode("current_mode_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(modeId, forKey: AnyCodingKey(stringValue: "currentModeId")!)
        case .configOptionUpdate(let configOptions):
            try container.encode("config_option_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(configOptions, forKey: AnyCodingKey(stringValue: "configOptions")!)
        }
    }
}

// MARK: - Tool Call Types

nonisolated struct ToolCallUpdate: Codable {
    let toolCallId: String
    let title: String?  // Optional for Codex compatibility
    let kind: ToolKind?  // Optional for Codex compatibility
    let status: ToolStatus
    let content: [ToolCallContent]
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title, kind, status, content, locations
        case rawInput
        case rawOutput
        case _meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decode(ToolStatus.self, forKey: .status)
        // content is optional for Codex which doesn't send it
        content = try container.decodeIfPresent([ToolCallContent].self, forKey: .content) ?? []
        locations = try container.decodeIfPresent([ToolLocation].self, forKey: .locations)
        rawInput = try container.decodeIfPresent(AnyCodable.self, forKey: .rawInput)
        rawOutput = try container.decodeIfPresent(AnyCodable.self, forKey: .rawOutput)
        _meta = try container.decodeIfPresent([String: AnyCodable].self, forKey: ._meta)

        // kind is optional - Codex may send it as string that needs mapping
        if let kindString = try? container.decode(String.self, forKey: .kind) {
            kind = ToolKind(rawValue: kindString)
        } else {
            kind = try container.decodeIfPresent(ToolKind.self, forKey: .kind)
        }
    }
}

nonisolated struct ToolCallUpdateDetails: Codable {
    let toolCallId: String
    let status: ToolStatus?
    let locations: [ToolLocation]?
    let kind: ToolKind?
    let title: String?
    let content: [ToolCallContent]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case status, locations, kind, title, content
        case rawInput
        case rawOutput
        case _meta
    }
}

// MARK: - Helper for encoding arbitrary keys

nonisolated struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - SessionUpdate Convenience Accessors

extension SessionUpdate {
    /// Discriminant for UI handling
    var sessionUpdate: String {
        switch self {
        case .userMessageChunk: return "user_message_chunk"
        case .agentMessageChunk: return "agent_message_chunk"
        case .agentThoughtChunk: return "agent_thought_chunk"
        case .toolCall: return "tool_call"
        case .toolCallUpdate: return "tool_call_update"
        case .plan: return "plan"
        case .availableCommandsUpdate: return "available_commands_update"
        case .currentModeUpdate: return "current_mode_update"
        case .configOptionUpdate: return "config_option_update"
        }
    }

    /// Raw content as JSON-friendly structure
    var content: AnyCodable? {
        switch self {
        case .userMessageChunk(let block),
             .agentMessageChunk(let block),
             .agentThoughtChunk(let block):
            return AnyCodable(block.toDictionary())
        case .toolCall(let call):
            let blocks = call.content.map { $0.toDictionary() }
            return AnyCodable(blocks)
        case .toolCallUpdate(let details):
            if let raw = details.rawOutput {
                return raw
            }
            return nil
        default:
            return nil
        }
    }

    var toolCalls: [ToolCall]? {
        switch self {
        case .toolCall(let update):
            return [
                ToolCall(
                    toolCallId: update.toolCallId,
                    title: update.title ?? (update.kind?.rawValue.capitalized ?? "Tool"),
                    kind: update.kind,
                    status: update.status,
                    content: update.content,
                    locations: update.locations,
                    rawInput: update.rawInput,
                    rawOutput: update.rawOutput,
                    timestamp: Date()
                )
            ]
        default:
            return nil
        }
    }

    var toolCallId: String? {
        switch self {
        case .toolCall(let update): return update.toolCallId
        case .toolCallUpdate(let details): return details.toolCallId
        default: return nil
        }
    }

    var title: String? {
        switch self {
        case .toolCall(let update): return update.title
        case .toolCallUpdate: return nil
        default: return nil
        }
    }

    var kind: ToolKind? {
        switch self {
        case .toolCall(let update): return update.kind
        default: return nil
        }
    }

    var status: ToolStatus? {
        switch self {
        case .toolCall(let update): return update.status
        case .toolCallUpdate(let details): return details.status
        default: return nil
        }
    }

    var locations: [ToolLocation]? {
        switch self {
        case .toolCall(let update): return update.locations
        case .toolCallUpdate(let details): return details.locations
        default: return nil
        }
    }

    var rawInput: AnyCodable? {
        switch self {
        case .toolCall(let update): return update.rawInput
        default: return nil
        }
    }

    var rawOutput: AnyCodable? {
        switch self {
        case .toolCall(let update): return update.rawOutput
        case .toolCallUpdate(let details): return details.rawOutput
        default: return nil
        }
    }

    var plan: Plan? {
        switch self {
        case .plan(let plan): return plan
        default: return nil
        }
    }

    var availableCommands: [AvailableCommand]? {
        switch self {
        case .availableCommandsUpdate(let commands): return commands
        default: return nil
        }
    }

    var currentMode: String? {
        switch self {
        case .currentModeUpdate(let mode): return mode
        default: return nil
        }
    }

    var configOptions: [SessionConfigOption]? {
        switch self {
        case .configOptionUpdate(let options): return options
        default: return nil
        }
    }
}

// MARK: - ContentBlock helpers

extension ContentBlock {
    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

extension ToolCallContent {
    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
