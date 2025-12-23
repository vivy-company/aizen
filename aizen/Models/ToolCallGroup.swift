//
//  ToolCallGroup.swift
//  aizen
//
//  Groups tool calls from a completed agent turn for display
//

import Foundation

struct ToolCallGroup: Identifiable {
    let iterationId: String
    var id: String { iterationId }
    var toolCalls: [ToolCall]
    let timestamp: Date

    init(iterationId: String, toolCalls: [ToolCall]) {
        self.iterationId = iterationId
        self.toolCalls = toolCalls.sorted { $0.timestamp < $1.timestamp }
        self.timestamp = toolCalls.first?.timestamp ?? Date.distantPast
    }

    /// Tool kinds used in this group (for icon display)
    var toolKinds: Set<ToolKind> {
        Set(toolCalls.map { $0.kind })
    }

    /// Summary text (e.g., "5 tool calls")
    var summaryText: String {
        String(localized: "\(toolCalls.count) tool calls")
    }

    /// All tool calls completed successfully
    var isSuccessful: Bool {
        toolCalls.allSatisfy { $0.status == .completed }
    }

    /// Any tool calls failed
    var hasFailed: Bool {
        toolCalls.contains { $0.status == .failed }
    }

    /// Any tool calls still in progress
    var isInProgress: Bool {
        toolCalls.contains { $0.status == .inProgress || $0.status == .pending }
    }
}
