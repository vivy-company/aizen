//
//  ToolCallGroup.swift
//  aizen
//
//  Groups tool calls from a completed agent turn for display
//

import ACP
import Foundation

// MARK: - File Change Summary

/// Summary of file changes for turn summary display
struct FileChangeSummary: Identifiable {
    let path: String
    let isNew: Bool
    var linesAdded: Int
    var linesRemoved: Int

    var id: String { path }

    /// Filename for display
    var filename: String {
        (path as NSString).lastPathComponent
    }

    /// Directory path for display
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

// MARK: - Tool Call Group

struct ToolCallGroup: Identifiable {
    /// Unique ID for this group (generated, not iterationId to avoid duplicates)
    let groupId: String
    let iterationId: String?
    var id: String { groupId }
    var toolCalls: [ToolCall]
    let timestamp: Date

    /// Message ID this group is associated with (the preceding message)
    var messageId: String?

    /// Turn timing for duration display
    var turnStartTime: Date?
    var turnEndTime: Date?

    /// Whether this group is from a completed turn (has subsequent message or streaming ended)
    var isCompletedTurn: Bool = false

    init(iterationId: String?, toolCalls: [ToolCall], messageId: String? = nil, isCompletedTurn: Bool = false) {
        // Generate unique ID from tool call IDs to ensure consistency across rebuilds
        let toolIds = toolCalls.map { $0.id }.sorted().joined(separator: "-")
        self.groupId = "group-\(toolIds.hashValue)"
        self.iterationId = iterationId
        self.toolCalls = toolCalls.sorted { $0.timestamp < $1.timestamp }
        self.timestamp = toolCalls.first?.timestamp ?? Date.distantPast
        self.messageId = messageId
        self.isCompletedTurn = isCompletedTurn

        // Calculate turn timing from tool calls
        if !toolCalls.isEmpty {
            self.turnStartTime = toolCalls.map { $0.timestamp }.min()
            self.turnEndTime = toolCalls.compactMap { call -> Date? in
                guard call.status == .completed || call.status == .failed else { return nil }
                return call.timestamp
            }.max()
        }
    }

    /// Tool kinds used in this group (for icon display)
    var toolKinds: Set<ToolKind> {
        Set(toolCalls.compactMap { $0.kind })
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

    /// Turn duration in seconds
    var turnDuration: TimeInterval? {
        guard let start = turnStartTime, let end = turnEndTime else { return nil }
        return end.timeIntervalSince(start)
    }

    /// Formatted turn duration string
    var formattedDuration: String? {
        guard let duration = turnDuration else { return nil }
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

    /// File changes extracted from edit/write tool calls
    var fileChanges: [FileChangeSummary] {
        var changes: [String: FileChangeSummary] = [:]

        for call in toolCalls where call.kind == .some(.edit) {
            // Extract file path from title or locations
            let filePath: String?
            if let path = call.locations?.first?.path {
                filePath = path
            } else if !call.title.isEmpty && call.title.contains("/") {
                filePath = call.title
            } else {
                filePath = nil
            }

            guard let path = filePath else { continue }

            // Calculate lines added/removed from diff content
            var linesAdded = 0
            var linesRemoved = 0
            var isNewFile = false

            for content in call.content {
                if case .diff(let diff) = content {
                    isNewFile = diff.oldText == nil || diff.oldText?.isEmpty == true

                    // Count lines in old and new text
                    let oldLines = diff.oldText?.components(separatedBy: "\n").count ?? 0
                    let newLines = diff.newText.components(separatedBy: "\n").count

                    if isNewFile {
                        linesAdded += newLines
                    } else {
                        // Simple approximation: difference in line count
                        if newLines > oldLines {
                            linesAdded += newLines - oldLines
                        } else {
                            linesRemoved += oldLines - newLines
                        }
                    }
                }
            }

            // Merge with existing entry for same file
            if var existing = changes[path] {
                existing.linesAdded += linesAdded
                existing.linesRemoved += linesRemoved
                changes[path] = existing
            } else {
                changes[path] = FileChangeSummary(
                    path: path,
                    isNew: isNewFile,
                    linesAdded: linesAdded,
                    linesRemoved: linesRemoved
                )
            }
        }

        return Array(changes.values).sorted { $0.path < $1.path }
    }

    /// Whether this group has file changes to show in summary
    var hasFileChanges: Bool {
        !fileChanges.isEmpty
    }
}
