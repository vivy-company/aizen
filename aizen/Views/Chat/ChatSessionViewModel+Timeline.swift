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

    // MARK: - Timeline

    /// Full rebuild - used only for initial load or major state changes
    func rebuildTimeline() {
        // Build timeline and deduplicate by stableId (keep first occurrence)
        var seen = Set<String>()
        timelineItems = (messages.map { .message($0) } + toolCalls.map { .toolCall($0) })
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert($0.stableId).inserted }
        timelineRenderEpoch &+= 1
        rebuildTimelineIndex()
    }

    /// Rebuild timeline with tool call grouping by message boundaries
    /// Flow: Message 1 → [Tool calls grouped] → Message 2 → [Tool calls grouped] → ...
    /// System messages (interrupts) appear after turn summaries and before the next user message
    func rebuildTimelineWithGrouping(isStreaming: Bool) {
        // Filter tool calls (skip children, they render inside parent)
        let topLevelCalls = toolCalls.filter { $0.parentToolCallId == nil }

        // Anchor restored tool calls to their owning message when available.
        // This preserves grouping boundaries even when persisted timestamps are coarse/equal.
        var anchoredTimestampByToolId: [String: Date] = [:]
        for message in messages {
            let topLevelMessageCalls = message.toolCalls.filter { $0.parentToolCallId == nil }
            guard !topLevelMessageCalls.isEmpty else { continue }
            for (index, call) in topLevelMessageCalls.enumerated() {
                let remaining = topLevelMessageCalls.count - index
                let offset = Double(remaining) * 0.000_001
                let anchored = message.timestamp.addingTimeInterval(-offset)
                if let existing = anchoredTimestampByToolId[call.id] {
                    if anchored < existing {
                        anchoredTimestampByToolId[call.id] = anchored
                    }
                } else {
                    anchoredTimestampByToolId[call.id] = anchored
                }
            }
        }

        // Create merged timeline entries sorted by timestamp (including system messages)
        enum EntryType {
            case message(MessageItem)
            case toolCall(ToolCall)
        }

        func sortPriority(for entryType: EntryType) -> Int {
            switch entryType {
            case .toolCall:
                return 1
            case .message(let message):
                switch message.role {
                case .user:
                    return 0
                case .agent:
                    return 2
                case .system:
                    return 3
                }
            }
        }

        var sequence = 0
        var entries: [(type: EntryType, timestamp: Date, priority: Int, sequence: Int)] = []
        for msg in messages {
            let entryType: EntryType = .message(msg)
            entries.append((entryType, msg.timestamp, sortPriority(for: entryType), sequence))
            sequence += 1
        }
        for call in topLevelCalls {
            let entryType: EntryType = .toolCall(call)
            let effectiveTimestamp = anchoredTimestampByToolId[call.id] ?? call.timestamp
            entries.append((entryType, effectiveTimestamp, sortPriority(for: entryType), sequence))
            sequence += 1
        }
        entries.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.sequence < rhs.sequence
        }

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
                        appendBufferedToolCalls(
                            toolCallBuffer,
                            messageId: lastAgentMessageId,
                            isCompletedTurn: false,
                            into: &items
                        )
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
                    appendBufferedToolCalls(
                        toolCallBuffer,
                        messageId: lastAgentMessageId,
                        isCompletedTurn: true,
                        into: &items
                    )
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
                // Still streaming - group exploration runs, keep other tools as individual rows.
                appendStreamingToolCallItems(
                    from: toolCallBuffer,
                    lastAgentMessageId: lastAgentMessageId,
                    into: &items
                )
            } else {
                // Streaming ended = TURN END
                appendBufferedToolCalls(
                    toolCallBuffer,
                    messageId: lastAgentMessageId,
                    isCompletedTurn: true,
                    into: &items
                )
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
        timelineRenderEpoch &+= 1
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

    /// Append buffered tool calls as a single row when possible; only create groups for 2+ calls.
    private func appendBufferedToolCalls(
        _ toolCalls: [ToolCall],
        messageId: String?,
        isCompletedTurn: Bool,
        into items: inout [TimelineItem]
    ) {
        guard !toolCalls.isEmpty else { return }
        if toolCalls.count == 1, let single = toolCalls.first {
            items.append(.toolCall(single))
            return
        }

        let group = createGroupFromBuffer(
            toolCalls: toolCalls,
            messageId: messageId,
            isCompletedTurn: isCompletedTurn
        )
        items.append(.toolCallGroup(group))
    }

    /// While streaming, show read/search/grep runs as expandable groups and keep other tools as standalone rows.
    private func appendStreamingToolCallItems(
        from toolCalls: [ToolCall],
        lastAgentMessageId: String?,
        into items: inout [TimelineItem]
    ) {
        var explorationBuffer: [ToolCall] = []

        func flushExplorationBuffer() {
            guard !explorationBuffer.isEmpty else { return }
            appendBufferedToolCalls(
                explorationBuffer,
                messageId: lastAgentMessageId,
                isCompletedTurn: false,
                into: &items
            )
            explorationBuffer.removeAll(keepingCapacity: true)
        }

        for call in toolCalls {
            if ToolCallGroup.isExplorationCandidate(call) {
                explorationBuffer.append(call)
                continue
            }

            flushExplorationBuffer()
            items.append(.toolCall(call))
        }

        flushExplorationBuffer()
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
                if !userScrolledUp {
                    scrollToBottomDeferred()
                }
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
                    timelineRenderEpoch &+= 1
                    timelineIndex = updatedIndex
                }
            }
        }

        updateBlock()

        // Update tracked IDs for next sync
        previousMessageIds = newIds

        // New message behavior:
        // - If user hasn't scrolled up, keep following bottom.
        // - If user scrolled up, do nothing (user is reading history).
        if !addedIds.isEmpty, !userScrolledUp {
            scrollToBottomDeferred()
        }
    }

    /// Sync tool calls incrementally - update existing or insert new
    func syncToolCalls(_ newToolCalls: [ToolCall]) {
        let newIds = Set(newToolCalls.map { $0.id })
        let addedIds = newIds.subtracting(previousToolCallIds)
        let removedIds = previousToolCallIds.subtracting(newIds)
        let hasStructuralChanges = !addedIds.isEmpty || !removedIds.isEmpty
        let isStreaming = currentAgentSession?.isStreaming ?? false

        if isStreaming {
            rebuildTimelineWithGrouping(isStreaming: true)
            previousToolCallIds = newIds
            if !addedIds.isEmpty, !userScrolledUp {
                scrollToBottomDeferred()
            }
            return
        }

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
                    timelineRenderEpoch &+= 1
                    timelineIndex = updatedIndex
                }
            }
        }

        updateBlock()

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

    // MARK: - Scrolling

    func scrollToBottom() {
        userScrolledUp = false
        requestScrollToBottom(force: true, animated: true)
    }

    /// Deferred scroll that avoids "ScrollViewProxy may not be accessed during view updates" crash
    func scrollToBottomDeferred() {
        scheduleAutoScrollToBottom()
    }

    private func requestScrollToBottom(force: Bool, animated: Bool) {
        scrollRequest = ScrollRequest(id: UUID(), target: .bottom, animated: animated, force: force)
    }

    private func scheduleAutoScrollToBottom() {
        guard !userScrolledUp else { return }
        guard !suppressNextAutoScroll else { return }
        guard autoScrollTask == nil else { return }

        autoScrollTask = Task { @MainActor in
            defer { autoScrollTask = nil }
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled || userScrolledUp || suppressNextAutoScroll {
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
