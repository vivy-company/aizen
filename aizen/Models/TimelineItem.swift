//
//  TimelineItem.swift
//  aizen
//
//  Timeline item combining messages and tool calls
//

import Foundation

enum TimelineItem {
    case message(MessageItem)
    case toolCall(ToolCall)
    case toolCallGroup(ToolCallGroup)

    /// Dynamic id that changes when content changes - used by SwiftUI ForEach to force re-renders
    var id: String {
        switch self {
        case .message(let msg):
            // Include content length so SwiftUI re-renders when streaming content changes
            return "\(msg.id)-\(msg.content.count)"
        case .toolCall(let tool):
            // Include status so SwiftUI re-renders when tool status changes
            return "\(tool.id)-\(tool.status.rawValue)"
        case .toolCallGroup(let group):
            // Include count and status so SwiftUI re-renders when group changes
            let statusKey = group.hasFailed ? "failed" : (group.isInProgress ? "progress" : "done")
            return "group-\(group.id)-\(group.toolCalls.count)-\(statusKey)"
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
        }
    }
}
