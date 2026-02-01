//
//  TimelineItem.swift
//  aizen
//
//  Timeline item combining messages and tool calls
//

import ACP
import Foundation

// MARK: - Turn Summary

/// Summary shown at the end of a completed turn
struct TurnSummary: Identifiable {
    let id: String
    let timestamp: Date
    let duration: TimeInterval
    let toolCallCount: Int
    let fileChanges: [FileChangeSummary]

    /// Formatted duration string
    var formattedDuration: String {
        if duration < 1 {
            return "<1s"
        } else if duration < 60 {
            return "\(Int(duration))s"
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Timeline Item

enum TimelineItem {
    case message(MessageItem)
    case toolCall(ToolCall)
    case toolCallGroup(ToolCallGroup)
    case turnSummary(TurnSummary)

    /// Dynamic id that changes when content changes - used by SwiftUI ForEach to force re-renders
    var id: String {
        switch self {
        case .message(let msg):
            // Include content length so SwiftUI re-renders when streaming content changes
            let completionKey = msg.isComplete ? "done" : "stream"
            return "\(msg.id)-\(msg.content.count)-\(msg.contentBlocks.count)-\(completionKey)"
        case .toolCall(let tool):
            // Include status so SwiftUI re-renders when tool status changes
            return "\(tool.id)-\(tool.status.rawValue)"
        case .toolCallGroup(let group):
            // Include count and status so SwiftUI re-renders when group changes
            let statusKey = group.hasFailed ? "failed" : (group.isInProgress ? "progress" : "done")
            return "group-\(group.id)-\(group.toolCalls.count)-\(statusKey)"
        case .turnSummary(let summary):
            return "summary-\(summary.id)"
        }
    }

    /// Stable id for indexing - doesn't change when content updates
    var stableId: String {
        switch self {
        case .message(let msg):
            return msg.id
        case .toolCall(let tool):
            return tool.id
        case .toolCallGroup(let group):
            return "group-\(group.id)"
        case .turnSummary(let summary):
            return "summary-\(summary.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case .message(let msg):
            return msg.timestamp
        case .toolCall(let tool):
            return tool.timestamp
        case .toolCallGroup(let group):
            return group.timestamp
        case .turnSummary(let summary):
            return summary.timestamp
        }
    }
}
