//
//  ACPToolTypes.swift
//  aizen
//
//  Agent Client Protocol - Tool Call Types
//

import Foundation

// MARK: - Tool Call Content

/// Content produced by a tool call - can be standard content, diff, or terminal
nonisolated enum ToolCallContent: Codable {
    case content(ContentBlock)
    case diff(ToolCallDiff)
    case terminal(ToolCallTerminal)

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case path, oldText, newText
        case terminalId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "content":
            let block = try container.decode(ContentBlock.self, forKey: .content)
            self = .content(block)
        case "diff":
            let diff = try ToolCallDiff(from: decoder)
            self = .diff(diff)
        case "terminal":
            let terminal = try ToolCallTerminal(from: decoder)
            self = .terminal(terminal)
        default:
            // Fallback: try to decode as text content for unknown types
            if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
                self = .content(.text(TextContent(text: text)))
            } else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown tool call content type: \(type)")
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .content(let block):
            try container.encode("content", forKey: .type)
            try container.encode(block, forKey: .content)
        case .diff(let diff):
            try container.encode("diff", forKey: .type)
            try diff.encode(to: encoder)
        case .terminal(let terminal):
            try container.encode("terminal", forKey: .type)
            try terminal.encode(to: encoder)
        }
    }

    /// Extract text content for display (best effort)
    var displayText: String? {
        switch self {
        case .content(let block):
            if case .text(let text) = block {
                return text.text
            }
            return nil
        case .diff(let diff):
            return "Modified: \(diff.path)"
        case .terminal(let terminal):
            return "Terminal: \(terminal.terminalId)"
        }
    }

    /// Convert to ContentBlock if possible (for backwards compatibility)
    var asContentBlock: ContentBlock? {
        switch self {
        case .content(let block):
            return block
        case .diff(let diff):
            // Convert diff to text for display
            var text = "File: \(diff.path)\n"
            if let old = diff.oldText {
                text += "--- old\n\(old)\n"
            }
            text += "+++ new\n\(diff.newText)"
            return .text(TextContent(text: text))
        case .terminal:
            return nil
        }
    }
}

nonisolated struct ToolCallDiff: Codable {
    let path: String
    let oldText: String?
    let newText: String

    enum CodingKeys: String, CodingKey {
        case path, oldText, newText
    }
}

nonisolated struct ToolCallTerminal: Codable {
    let terminalId: String

    enum CodingKeys: String, CodingKey {
        case terminalId
    }
}

// MARK: - Tool Calls

nonisolated struct ToolCall: Codable, Identifiable {
    let toolCallId: String
    var title: String
    var kind: ToolKind?  // Optional for Codex compatibility
    var status: ToolStatus
    var content: [ToolCallContent]
    var locations: [ToolLocation]?
    var rawInput: AnyCodable?
    var rawOutput: AnyCodable?
    var timestamp: Date = Date()
    var iterationId: String?
    var parentToolCallId: String?  // Parent Task's toolCallId for nested tool calls

    var id: String { toolCallId }

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title, kind, status, content, locations
        case rawInput
        case rawOutput
    }

    /// Resolved kind for display - defaults to .other if not provided
    var resolvedKind: ToolKind {
        kind ?? .other
    }

    /// Get content as ContentBlocks for backwards compatibility with existing UI
    var contentBlocks: [ContentBlock] {
        content.compactMap { $0.asContentBlock }
    }
}

nonisolated enum ToolKind: String, Codable {
    case read
    case edit
    case delete
    case move
    case search
    case execute
    case think
    case fetch
    case switchMode = "switch_mode"
    case plan
    case exitPlanMode = "exit_plan_mode"
    case other

    /// SF Symbol name for this tool kind
    var symbolName: String {
        switch self {
        case .read: return "doc.text"
        case .edit: return "pencil"
        case .delete: return "trash"
        case .move: return "arrow.right.doc.on.clipboard"
        case .search: return "magnifyingglass"
        case .execute: return "terminal"
        case .think: return "brain"
        case .fetch: return "arrow.down.circle"
        case .switchMode: return "arrow.left.arrow.right"
        case .plan: return "list.bullet.clipboard"
        case .exitPlanMode: return "checkmark.circle"
        case .other: return "wrench.and.screwdriver"
        }
    }
}

nonisolated enum ToolStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case failed
}

nonisolated struct ToolLocation: Codable {
    let path: String?
    let line: Int?  // Line number (0-indexed position)
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, _meta
    }
}

// MARK: - Available Commands

nonisolated struct AvailableCommand: Codable {
    let name: String
    let description: String
    let input: CommandInputSpec?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, description, input, _meta
    }
}

nonisolated struct CommandInputSpec: Codable {
    let type: String?
    let hint: String?  // Codex uses this instead of type
    let properties: [String: AnyCodable]?
    let required: [String]?
}

// MARK: - Agent Plan

nonisolated enum PlanPriority: String, Codable {
    case low
    case medium
    case high
}

nonisolated enum PlanEntryStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

nonisolated struct PlanEntry: Codable, Equatable {
    let content: String
    let priority: PlanPriority
    let status: PlanEntryStatus
    let activeForm: String?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content, priority, status, activeForm, _meta
    }

    static func == (lhs: PlanEntry, rhs: PlanEntry) -> Bool {
        // Compare relevant fields, ignore _meta for equality
        lhs.content == rhs.content &&
        lhs.priority == rhs.priority &&
        lhs.status == rhs.status &&
        lhs.activeForm == rhs.activeForm
    }
}

nonisolated struct Plan: Codable, Equatable {
    let entries: [PlanEntry]
}
