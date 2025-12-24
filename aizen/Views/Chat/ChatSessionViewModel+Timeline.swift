//
//  ChatSessionViewModel+Timeline.swift
//  aizen
//
//  Timeline and scrolling operations for chat sessions
//

import Foundation
import ObjectiveC
import SwiftUI
import Combine

// MARK: - Timeline Index Storage
private var timelineIndexKey: UInt8 = 0

extension ChatSessionViewModel {
    // MARK: - Timeline Index (O(1) Lookup)

    /// Dictionary for O(1) timeline item lookups by ID
    private var timelineIndex: [String: Int] {
        get {
            objc_getAssociatedObject(self, &timelineIndexKey) as? [String: Int] ?? [:]
        }
        set {
            objc_setAssociatedObject(self, &timelineIndexKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Rebuild the timeline index from current items (uses stableId for consistent lookups)
    private func rebuildTimelineIndex() {
        // Use uniquingKeysWith to handle duplicates gracefully (keep last index)
        timelineIndex = Dictionary(
            timelineItems.enumerated().map { ($1.stableId, $0) },
            uniquingKeysWith: { _, new in new }
        )
    }

    // MARK: - Timeline

    /// Full rebuild - used only for initial load or major state changes
    func rebuildTimeline() {
        // Build timeline and deduplicate by stableId (keep first occurrence)
        var seen = Set<String>()
        timelineItems = (messages.map { .message($0) } + toolCalls.map { .toolCall($0) })
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert($0.stableId).inserted }
        rebuildTimelineIndex()
    }

    /// Rebuild timeline with tool call grouping by message boundaries
    /// Flow: Message 1 → [Tool calls grouped] → Message 2 → [Tool calls grouped] → ...
    func rebuildTimelineWithGrouping(isStreaming: Bool) {
        // Filter tool calls (skip children, they render inside parent)
        let topLevelCalls = toolCalls.filter { $0.parentToolCallId == nil }

        // Create merged timeline entries sorted by timestamp
        enum EntryType {
            case message(MessageItem)
            case toolCall(ToolCall)
        }

        var entries: [(type: EntryType, timestamp: Date)] = []
        for msg in messages {
            entries.append((.message(msg), msg.timestamp))
        }
        for call in topLevelCalls {
            entries.append((.toolCall(call), call.timestamp))
        }
        entries.sort { $0.timestamp < $1.timestamp }

        // Build timeline: group tool calls when next agent message arrives
        var items: [TimelineItem] = []
        var toolCallBuffer: [ToolCall] = []
        var lastAgentMessageId: String?

        for entry in entries {
            switch entry.type {
            case .message(let msg):
                // Group buffered tool calls when:
                // 1. A new agent message arrives (normal turn end)
                // 2. A user message arrives (agent was interrupted)
                if !toolCallBuffer.isEmpty && (msg.role == .agent || msg.role == .user) {
                    let group = createGroupFromBuffer(
                        toolCalls: toolCallBuffer,
                        messageId: lastAgentMessageId,
                        isCompletedTurn: msg.role == .agent
                    )
                    items.append(.toolCallGroup(group))

                    // Add turn summary after this group
                    let summary = createTurnSummary(from: toolCallBuffer)
                    if summary.fileChanges.count > 0 || summary.duration > 0 {
                        items.append(.turnSummary(summary))
                    }

                    toolCallBuffer = []
                }

                items.append(.message(msg))

                if msg.role == .agent {
                    lastAgentMessageId = msg.id
                }

            case .toolCall(let call):
                toolCallBuffer.append(call)
            }
        }

        // Handle remaining tool calls after last message
        if !toolCallBuffer.isEmpty {
            if isStreaming {
                // Still streaming - show individual tool calls
                for call in toolCallBuffer {
                    items.append(.toolCall(call))
                }
            } else {
                // Turn ended - create final group
                let group = createGroupFromBuffer(
                    toolCalls: toolCallBuffer,
                    messageId: lastAgentMessageId,
                    isCompletedTurn: true
                )
                items.append(.toolCallGroup(group))

                // Add turn summary for final group
                let summary = createTurnSummary(from: toolCallBuffer)
                if summary.fileChanges.count > 0 || summary.duration > 0 {
                    items.append(.turnSummary(summary))
                }
            }
        }

        timelineItems = items
        rebuildTimelineIndex()
    }

    /// Create turn summary from all tool calls in the turn
    private func createTurnSummary(from toolCalls: [ToolCall]) -> TurnSummary {
        // Calculate duration from first to last tool call
        let timestamps = toolCalls.map { $0.timestamp }
        let startTime = timestamps.min() ?? Date()
        let endTime = timestamps.max() ?? Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Collect file changes from all edit tool calls
        var fileChanges: [String: FileChangeSummary] = [:]

        for call in toolCalls where call.kind == .edit {
            let filePath: String?
            if let path = call.locations?.first?.path {
                filePath = path
            } else if !call.title.isEmpty && call.title.contains("/") {
                filePath = call.title
            } else {
                filePath = nil
            }

            guard let path = filePath else { continue }

            var linesAdded = 0
            var linesRemoved = 0
            var isNewFile = false

            for content in call.content {
                if case .diff(let diff) = content {
                    isNewFile = diff.oldText == nil || diff.oldText?.isEmpty == true
                    let oldLines = diff.oldText?.components(separatedBy: "\n").count ?? 0
                    let newLines = diff.newText.components(separatedBy: "\n").count

                    if isNewFile {
                        linesAdded += newLines
                    } else {
                        if newLines > oldLines {
                            linesAdded += newLines - oldLines
                        } else {
                            linesRemoved += oldLines - newLines
                        }
                    }
                }
            }

            if var existing = fileChanges[path] {
                existing.linesAdded += linesAdded
                existing.linesRemoved += linesRemoved
                fileChanges[path] = existing
            } else {
                fileChanges[path] = FileChangeSummary(
                    path: path,
                    isNew: isNewFile,
                    linesAdded: linesAdded,
                    linesRemoved: linesRemoved
                )
            }
        }

        return TurnSummary(
            id: UUID().uuidString,
            timestamp: endTime,
            duration: duration,
            fileChanges: Array(fileChanges.values).sorted { $0.path < $1.path }
        )
    }

    /// Create a tool call group from buffered calls
    private func createGroupFromBuffer(toolCalls: [ToolCall], messageId: String?, isCompletedTurn: Bool) -> ToolCallGroup {
        // Use first call's iterationId or generate one
        let iterationId = toolCalls.first?.iterationId ?? UUID().uuidString
        return ToolCallGroup(
            iterationId: iterationId,
            toolCalls: toolCalls,
            messageId: messageId,
            isCompletedTurn: isCompletedTurn
        )
    }

    /// Sync messages incrementally - update existing or insert new
    /// When a new agent message is added, triggers timeline rebuild to group preceding tool calls
    func syncMessages(_ newMessages: [MessageItem]) {
        let newIds = Set(newMessages.map { $0.id })
        let addedIds = newIds.subtracting(previousMessageIds)
        let removedIds = previousMessageIds.subtracting(newIds)
        let hasStructuralChanges = !addedIds.isEmpty || !removedIds.isEmpty

        // Check if any newly added messages are agent messages (triggers grouping)
        let newAgentMessageAdded = newMessages.contains { msg in
            addedIds.contains(msg.id) && msg.role == .agent
        }

        // If a new agent message arrived, rebuild with grouping to collapse previous tool calls
        if newAgentMessageAdded {
            let isStreaming = currentAgentSession?.isStreaming ?? false
            // Skip animation during streaming to prevent layout issues
            if isStreaming {
                rebuildTimelineWithGrouping(isStreaming: isStreaming)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    rebuildTimelineWithGrouping(isStreaming: isStreaming)
                }
            }
            previousMessageIds = newIds
            return
        }

        var didMutate = false

        let updateBlock = { [self] in
            // 0. Remove any messages that no longer exist
            if !removedIds.isEmpty {
                timelineItems.removeAll { removedIds.contains($0.stableId) }
                didMutate = true
            }

            // 1. Insert new messages FIRST (changes structure/indices)
            for newMsg in newMessages where addedIds.contains(newMsg.id) {
                insertTimelineItem(.message(newMsg))
                didMutate = true
            }

            // 2. Rebuild index IMMEDIATELY after structural changes
            if hasStructuralChanges {
                rebuildTimelineIndex()
            }

            // 3. Update existing messages AFTER index is fresh
            for newMsg in newMessages where previousMessageIds.contains(newMsg.id) {
                if let idx = timelineIndex[newMsg.id], idx < timelineItems.count {
                    timelineItems[idx] = .message(newMsg)
                    didMutate = true
                }
            }
        }

        // Only animate structural changes after initial load
        if hasStructuralChanges && !previousMessageIds.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) { updateBlock() }
        } else {
            updateBlock()
        }

        // Force publish for in-place mutations (content updates during streaming).
        if didMutate {
            timelineItems = timelineItems
        }

        // Update tracked IDs for next sync
        previousMessageIds = newIds
    }

    /// Sync tool calls incrementally - update existing or insert new
    func syncToolCalls(_ newToolCalls: [ToolCall]) {
        let newIds = Set(newToolCalls.map { $0.id })
        let addedIds = newIds.subtracting(previousToolCallIds)
        let removedIds = previousToolCallIds.subtracting(newIds)
        let hasStructuralChanges = !addedIds.isEmpty || !removedIds.isEmpty
        var didMutate = false

        let updateBlock = { [self] in
            // 0. Remove any tool calls that no longer exist
            if !removedIds.isEmpty {
                timelineItems.removeAll { removedIds.contains($0.stableId) }
                didMutate = true
            }

            // 1. Insert new tool calls FIRST (changes structure/indices)
            for newCall in newToolCalls where addedIds.contains(newCall.id) {
                insertTimelineItem(.toolCall(newCall))
                didMutate = true
            }

            // 2. Rebuild index IMMEDIATELY after structural changes
            if hasStructuralChanges {
                rebuildTimelineIndex()
            }

            // 3. Update existing tool calls AFTER index is fresh
            for newCall in newToolCalls where previousToolCallIds.contains(newCall.id) {
                if let idx = timelineIndex[newCall.id], idx < timelineItems.count {
                    timelineItems[idx] = .toolCall(newCall)
                    didMutate = true
                }
            }
        }

        // Only animate structural changes after initial load and when not streaming
        let isStreaming = currentAgentSession?.isStreaming ?? false
        if hasStructuralChanges && !previousToolCallIds.isEmpty && !isStreaming {
            withAnimation(.easeInOut(duration: 0.2)) { updateBlock() }
        } else {
            updateBlock()
        }

        // Force publish for in-place mutations.
        if didMutate {
            timelineItems = timelineItems
        }

        // Update tracked IDs for next sync
        previousToolCallIds = newIds
    }

    /// Insert timeline item maintaining sorted order by timestamp
    private func insertTimelineItem(_ item: TimelineItem) {
        // Skip if item already exists (prevent duplicates)
        if timelineItems.contains(where: { $0.stableId == item.stableId }) {
            return
        }

        let timestamp = item.timestamp

        // Binary search for insert position
        var low = 0
        var high = timelineItems.count

        while low < high {
            let mid = (low + high) / 2
            if timelineItems[mid].timestamp < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }

        timelineItems.insert(item, at: low)
    }

    // MARK: - Tool Call Grouping

    /// Get child tool calls for a parent Task
    func childToolCalls(for parentId: String) -> [ToolCall] {
        toolCalls.filter { $0.parentToolCallId == parentId }
    }

    /// Check if a tool call has children (is a Task with nested calls)
    func hasChildToolCalls(toolCallId: String) -> Bool {
        toolCalls.contains { $0.parentToolCallId == toolCallId }
    }

    // MARK: - Scrolling

    func scrollToBottom() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.3)) {
                // Always scroll to bottom_anchor to ensure everything including
                // processing indicator is visible
                scrollProxy?.scrollTo("bottom_anchor", anchor: .bottom)
            }
        }
    }
}
