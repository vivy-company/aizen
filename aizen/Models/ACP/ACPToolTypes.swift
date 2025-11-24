//
//  ACPToolTypes.swift
//  aizen
//
//  Agent Client Protocol - Tool Call Types
//

import Foundation

// MARK: - Tool Calls

struct ToolCall: Codable, Identifiable {
    let toolCallId: String
    let title: String
    let kind: ToolKind
    let status: ToolStatus
    let content: [ContentBlock]
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?
    var timestamp: Date = Date()

    var id: String { toolCallId }

    enum CodingKeys: String, CodingKey {
        case toolCallId = "tool_call_id"
        case title, kind, status, content, locations
        case rawInput = "raw_input"
        case rawOutput = "raw_output"
    }
}

enum ToolKind: String, Codable {
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
}

enum ToolStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case failed
}

struct ToolLocation: Codable {
    let path: String?
    let startLine: Int?
    let endLine: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case startLine
        case endLine
    }
}

// MARK: - Available Commands

struct AvailableCommand: Codable {
    let name: String
    let description: String
    let inputSpec: CommandInputSpec?

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSpec = "input_spec"
    }
}

struct CommandInputSpec: Codable {
    let type: String
    let properties: [String: AnyCodable]?
    let required: [String]?
}

// MARK: - Agent Plan

struct PlanEntry: Codable {
    let content: String
    let activeForm: String?
    let status: PlanEntryStatus

    enum CodingKeys: String, CodingKey {
        case content
        case activeForm = "active_form"
        case status
    }
}

enum PlanEntryStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

struct Plan: Codable {
    let entries: [PlanEntry]
}
