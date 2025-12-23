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

    /// Rebuild timeline with tool call grouping for completed turns
    func rebuildTimelineWithGrouping(isStreaming: Bool) {
        let currentIterationId = currentAgentSession?.currentIterationId

        // Group tool calls by iterationId
        var groupsByIteration: [String: [ToolCall]] = [:]
        var ungroupedCalls: [ToolCall] = []

        for call in toolCalls {
            // Skip child tool calls (they're rendered inside their parent)
            guard call.parentToolCallId == nil else { continue }

            if let iterationId = call.iterationId {
                let isCurrentIteration = iterationId == currentIterationId
                if isStreaming && isCurrentIteration {
                    // Current turn during streaming - keep individual
                    ungroupedCalls.append(call)
                } else {
                    groupsByIteration[iterationId, default: []].append(call)
                }
            } else {
                // No iteration ID - keep individual
                ungroupedCalls.append(call)
            }
        }

        // Build timeline items
        var items: [TimelineItem] = messages.map { .message($0) }

        // Add grouped tool calls
        for (iterationId, calls) in groupsByIteration where !calls.isEmpty {
            let group = ToolCallGroup(iterationId: iterationId, toolCalls: calls)
            items.append(.toolCallGroup(group))
        }

        // Add ungrouped tool calls
        for call in ungroupedCalls {
            items.append(.toolCall(call))
        }

        // Sort by timestamp
        timelineItems = items.sorted { $0.timestamp < $1.timestamp }
        rebuildTimelineIndex()
    }

    /// Sync messages incrementally - update existing or insert new
    func syncMessages(_ newMessages: [MessageItem]) {
        let newIds = Set(newMessages.map { $0.id })
        let addedIds = newIds.subtracting(previousMessageIds)
        let removedIds = previousMessageIds.subtracting(newIds)
        let hasStructuralChanges = !addedIds.isEmpty || !removedIds.isEmpty
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

        // Only animate structural changes after initial load
        if hasStructuralChanges && !previousToolCallIds.isEmpty {
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
                if let lastMessage = messages.last {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                } else if isProcessing {
                    scrollProxy?.scrollTo("processing", anchor: .bottom)
                }
            }
        }
    }
}
