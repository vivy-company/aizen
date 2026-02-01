//
//  ChatSessionViewModel+Timeline.swift
//  aizen
//
//  Timeline and scrolling operations for chat sessions
//

import ACP
import Combine
import Foundation
import ObjectiveC
import os
import SwiftUI

// MARK: - Timeline Index Storage
private var timelineIndexKey: UInt8 = 0

extension ChatSessionViewModel {
    struct ScrollRequest: Equatable {
        enum Target: Equatable {
            case bottom
            case item(id: String, anchor: UnitPoint)
        }

        let id: UUID
        let target: Target
        let animated: Bool
        let force: Bool
    }

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

    private func makeTimelineIndex(from items: [TimelineItem]) -> [String: Int] {
        // Use uniquingKeysWith to handle duplicates gracefully (keep last index)
        Dictionary(
            items.enumerated().map { ($1.stableId, $0) },
            uniquingKeysWith: { _, new in new }
        )
    }

    /// Rebuild the timeline index from current items (uses stableId for consistent lookups)
    private func rebuildTimelineIndex() {
        rebuildTimelineIndex(from: timelineItems)
    }

    private func rebuildTimelineIndex(from items: [TimelineItem]) {
        timelineIndex = makeTimelineIndex(from: items)
    }

    /// Rebuild child tool call index for quick lookup in views
    private func rebuildChildToolCallsIndex() {
        var index: [String: [ToolCall]] = [:]
        for call in toolCalls {
            guard let parent = call.parentToolCallId else { continue }
            index[parent, default: []].append(call)
        }
        childToolCallsByParentId = index
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
        rebuildChildToolCallsIndex()
    }

    /// Rebuild timeline with tool call grouping by message boundaries
    /// Flow: Message 1 → [Tool calls grouped] → Message 2 → [Tool calls grouped] → ...
    /// System messages (interrupts) appear after turn summaries and before the next user message
    func rebuildTimelineWithGrouping(isStreaming: Bool) {
        // Filter tool calls (skip children, they render inside parent)
        let topLevelCalls = toolCalls.filter { $0.parentToolCallId == nil }

        // Create merged timeline entries sorted by timestamp (including system messages)
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

        // Build timeline: group tool calls at message boundaries
        // Turn summary ONLY appears when turn actually ends:
        // 1. User sends new message (interrupts/follows agent)
        // 2. Streaming ends (agent finishes responding)
        // System messages (interrupts) are buffered and inserted after turn summaries
        var items: [TimelineItem] = []
        var toolCallBuffer: [ToolCall] = []
        var turnToolCalls: [ToolCall] = []  // Accumulate all tool calls in current turn
        var lastAgentMessageId: String?
        var pendingSystemMessages: [MessageItem] = []  // System messages waiting for turn end

        for entry in entries {
            switch entry.type {
            case .message(let msg):
                // System messages are buffered until turn ends
                if msg.role == .system {
                    pendingSystemMessages.append(msg)
                    continue
                }

                // User message = TURN BOUNDARY
                if msg.role == .user {
                    // Group any remaining buffered tool calls
                    if !toolCallBuffer.isEmpty {
                        let group = createGroupFromBuffer(
                            toolCalls: toolCallBuffer,
                            messageId: lastAgentMessageId,
                            isCompletedTurn: false
                        )
                        items.append(.toolCallGroup(group))
                        turnToolCalls.append(contentsOf: toolCallBuffer)
                        toolCallBuffer = []
                    }
                    // Add turn summary for the completed turn (before user message)
                    if !turnToolCalls.isEmpty {
                        let summary = createTurnSummary(from: turnToolCalls)
                        items.append(.turnSummary(summary))
                        turnToolCalls = []  // Reset for next turn
                    }
                    // Add pending system messages after turn summary, before user message
                    for sysMsg in pendingSystemMessages {
                        items.append(.message(sysMsg))
                    }
                    pendingSystemMessages = []
                }

                // Agent message after tools: just group them (turn not over yet)
                if msg.role == .agent && !toolCallBuffer.isEmpty {
                    let group = createGroupFromBuffer(
                        toolCalls: toolCallBuffer,
                        messageId: lastAgentMessageId,
                        isCompletedTurn: true
                    )
                    items.append(.toolCallGroup(group))
                    turnToolCalls.append(contentsOf: toolCallBuffer)
                    toolCallBuffer = []
                    // NO summary here - turn continues
                }

                items.append(.message(msg))

                if msg.role == .agent {
                    lastAgentMessageId = msg.id
                }

            case .toolCall(let call):
                toolCallBuffer.append(call)
            }
        }

        // Handle remaining tool calls after all messages
        if !toolCallBuffer.isEmpty {
            turnToolCalls.append(contentsOf: toolCallBuffer)
            if isStreaming {
                // Still streaming - show individual tool calls (no summary)
                for call in toolCallBuffer {
                    items.append(.toolCall(call))
                }
            } else {
                // Streaming ended = TURN END
                let group = createGroupFromBuffer(
                    toolCalls: toolCallBuffer,
                    messageId: lastAgentMessageId,
                    isCompletedTurn: true
                )
                items.append(.toolCallGroup(group))
                let summary = createTurnSummary(from: turnToolCalls)
                items.append(.turnSummary(summary))
                // Add pending system messages after final turn summary
                for sysMsg in pendingSystemMessages {
                    items.append(.message(sysMsg))
                }
                pendingSystemMessages = []
            }
        } else if !isStreaming && !turnToolCalls.isEmpty {
            // Turn ended with agent message after tools - add summary now
            let summary = createTurnSummary(from: turnToolCalls)
            items.append(.turnSummary(summary))
            // Add pending system messages after final turn summary
            for sysMsg in pendingSystemMessages {
                items.append(.message(sysMsg))
            }
            pendingSystemMessages = []
        }

        // Any remaining system messages (e.g., if no turn was active) go at the end
        for sysMsg in pendingSystemMessages {
            items.append(.message(sysMsg))
        }

        timelineItems = items
        rebuildTimelineIndex()
        rebuildChildToolCallsIndex()
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

        for call in toolCalls where call.kind == .some(.edit) {
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
            toolCallCount: toolCalls.count,
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
        let isStreaming = currentAgentSession?.isStreaming ?? false

        // Check if any newly added messages are agent messages (triggers grouping)
        let newAgentMessageAdded = newMessages.contains { msg in
            addedIds.contains(msg.id) && msg.role == .agent
        }

        // If a new agent message arrived, rebuild with grouping to collapse previous tool calls
        if newAgentMessageAdded {
            // Skip animation during streaming to prevent layout issues
            rebuildTimelineWithGrouping(isStreaming: isStreaming)
            previousMessageIds = newIds
            return
        }

        // Fast path: no structural changes during streaming - update only the last agent message.
        if !hasStructuralChanges, let lastAgentMessage = newMessages.last(where: { $0.role == .agent }) {
            if let idx = timelineIndex[lastAgentMessage.id], idx < timelineItems.count {
                if case .message(let existing) = timelineItems[idx], existing == lastAgentMessage {
                    previousMessageIds = newIds
                    return
                }
                var updatedItems = timelineItems
                updatedItems[idx] = .message(lastAgentMessage)
                timelineItems = updatedItems
                previousMessageIds = newIds
                return
            }
        }

        let updateBlock = { [self] in
            var updatedItems = timelineItems
            var updatedIndex = timelineIndex
            var didMutate = false

            // 0. Remove any messages that no longer exist
            if !removedIds.isEmpty {
                updatedItems.removeAll { removedIds.contains($0.stableId) }
                didMutate = true
            }

            // 1. Insert new messages FIRST (changes structure/indices)
            for newMsg in newMessages where addedIds.contains(newMsg.id) {
                if isStreaming {
                    if !updatedItems.contains(where: { $0.stableId == newMsg.id }) {
                        updatedItems.append(.message(newMsg))
                        didMutate = true
                    }
                } else {
                    insertTimelineItem(.message(newMsg), into: &updatedItems)
                    didMutate = true
                }
            }

            // 2. Rebuild index IMMEDIATELY after structural changes
            if hasStructuralChanges {
                updatedIndex = makeTimelineIndex(from: updatedItems)
            }

            // 3. Update existing messages AFTER index is fresh
            for newMsg in newMessages where previousMessageIds.contains(newMsg.id) {
                if let idx = updatedIndex[newMsg.id], idx < updatedItems.count {
                    updatedItems[idx] = .message(newMsg)
                    didMutate = true
                }
            }

            if didMutate {
                timelineItems = updatedItems
                if hasStructuralChanges {
                    timelineIndex = updatedIndex
                }
            }
        }

        updateBlock()

        // Update tracked IDs for next sync
        previousMessageIds = newIds

        // New message behavior:
        // - If pinned, keep following bottom.
        // - If not pinned, do nothing (user is reading history).
        if !addedIds.isEmpty, isNearBottom {
            requestScrollToBottom(force: false, animated: false)
        }
    }

    /// Sync tool calls incrementally - update existing or insert new
    func syncToolCalls(_ newToolCalls: [ToolCall]) {
        let newIds = Set(newToolCalls.map { $0.id })
        let addedIds = newIds.subtracting(previousToolCallIds)
        let removedIds = previousToolCallIds.subtracting(newIds)
        let hasStructuralChanges = !addedIds.isEmpty || !removedIds.isEmpty
        let isStreaming = currentAgentSession?.isStreaming ?? false
        let updateBlock = { [self] in
            var updatedItems = timelineItems
            var updatedIndex = timelineIndex
            var didMutate = false

            // 0. Remove any tool calls that no longer exist
            if !removedIds.isEmpty {
                updatedItems.removeAll { removedIds.contains($0.stableId) }
                didMutate = true
            }

            // 1. Insert new tool calls FIRST (changes structure/indices)
            for newCall in newToolCalls where addedIds.contains(newCall.id) {
                if isStreaming {
                    if !updatedItems.contains(where: { $0.stableId == newCall.id }) {
                        updatedItems.append(.toolCall(newCall))
                        didMutate = true
                    }
                } else {
                    insertTimelineItem(.toolCall(newCall), into: &updatedItems)
                    didMutate = true
                }
            }

            // 2. Rebuild index IMMEDIATELY after structural changes
            if hasStructuralChanges {
                updatedIndex = makeTimelineIndex(from: updatedItems)
            }

            // 3. Update existing tool calls AFTER index is fresh
            for newCall in newToolCalls where previousToolCallIds.contains(newCall.id) {
                if let idx = updatedIndex[newCall.id], idx < updatedItems.count {
                    updatedItems[idx] = .toolCall(newCall)
                    didMutate = true
                }
            }

            if didMutate {
                timelineItems = updatedItems
                if hasStructuralChanges {
                    timelineIndex = updatedIndex
                }
            }
        }

        updateBlock()

        rebuildChildToolCallsIndex()

        // Update tracked IDs for next sync
        previousToolCallIds = newIds
    }

    /// Insert timeline item maintaining sorted order by timestamp
    private func insertTimelineItem(_ item: TimelineItem, into items: inout [TimelineItem]) {
        // Skip if item already exists (prevent duplicates)
        if items.contains(where: { $0.stableId == item.stableId }) {
            return
        }

        let timestamp = item.timestamp

        // Binary search for insert position
        var low = 0
        var high = items.count

        while low < high {
            let mid = (low + high) / 2
            if items[mid].timestamp < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }

        items.insert(item, at: low)
    }

    // MARK: - Tool Call Grouping

    /// Get child tool calls for a parent Task
    func childToolCalls(for parentId: String) -> [ToolCall] {
        childToolCallsByParentId[parentId] ?? []
    }

    /// Check if a tool call has children (is a Task with nested calls)
    func hasChildToolCalls(toolCallId: String) -> Bool {
        !(childToolCallsByParentId[toolCallId]?.isEmpty ?? true)
    }

    // MARK: - Scrolling

    func scrollToBottom() {
        requestScrollToBottom(force: true, animated: true)
    }

    /// Deferred scroll that avoids "ScrollViewProxy may not be accessed during view updates" crash
    func scrollToBottomDeferred() {
        scheduleAutoScrollToBottom()
    }

    private func requestScrollToBottom(force: Bool, animated: Bool) {
        scrollRequest = ScrollRequest(id: UUID(), target: .bottom, animated: animated, force: force)
    }

    private func requestScrollToItem(id: String, anchor: UnitPoint, force: Bool, animated: Bool) {
        scrollRequest = ScrollRequest(
            id: UUID(),
            target: .item(id: id, anchor: anchor),
            animated: animated,
            force: force
        )
    }

    private func scheduleAutoScrollToBottom() {
        guard isNearBottom else { return }
        guard autoScrollTask == nil else { return }

        autoScrollTask = Task { @MainActor in
            defer { autoScrollTask = nil }
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled || !isNearBottom {
                return
            }
            scrollRequest = ScrollRequest(id: UUID(), target: .bottom, animated: false, force: false)
        }
    }

    func cancelPendingAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
}
