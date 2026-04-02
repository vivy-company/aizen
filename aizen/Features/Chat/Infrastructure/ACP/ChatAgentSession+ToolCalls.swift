import ACP
import Foundation

extension ChatAgentSession {
    // MARK: - Tool Call Management (O(1) Dictionary Operations)

    /// Get tool call by ID (O(1) lookup)
    func getToolCall(id: String) -> ToolCall? {
        toolCallsById[id]
    }

    /// Insert or update a tool call (O(1) operation)
    func upsertToolCall(_ toolCall: ToolCall) {
        let id = toolCall.toolCallId
        if toolCallsById[id] == nil {
            toolCallOrder.append(id)
        }
        toolCallsById[id] = toolCall
        trimToolCallsIfNeeded()
    }

    /// Update an existing tool call in place (O(1) operation)
    func updateToolCallInPlace(id: String, update: (inout ToolCall) -> Void) {
        guard var toolCall = toolCallsById[id] else { return }
        let before = toolCall
        update(&toolCall)
        if toolCallChanged(before: before, after: toolCall) {
            toolCallsById[id] = toolCall
        }
    }

    /// Clear all tool calls
    func clearToolCalls() {
        toolCallsById.removeAll()
        toolCallOrder.removeAll()
        pendingToolCallUpdatesById.removeAll()
        persistedToolCallIds.removeAll()
    }

    func loadPersistedToolCalls(_ toolCalls: [ToolCall]) {
        clearToolCalls()
        let sortedCalls = toolCalls.enumerated().sorted { lhs, rhs in
            if lhs.element.timestamp != rhs.element.timestamp {
                return lhs.element.timestamp < rhs.element.timestamp
            }
            return lhs.offset < rhs.offset
        }
        for entry in sortedCalls {
            let call = entry.element
            upsertToolCall(call)
            persistedToolCallIds.insert(call.toolCallId)
        }
    }

    private func trimToolCallsIfNeeded() {
        let excess = toolCallOrder.count - Self.maxToolCallCount
        guard excess > 0 else { return }
        let idsToRemove = toolCallOrder.prefix(excess)
        for id in idsToRemove {
            toolCallsById.removeValue(forKey: id)
        }
        toolCallOrder.removeFirst(excess)
    }

    private func toolCallChanged(before: ToolCall, after: ToolCall) -> Bool {
        if before.title != after.title { return true }
        if before.kind?.rawValue != after.kind?.rawValue { return true }
        if before.status != after.status { return true }
        if before.content.count != after.content.count { return true }
        if !toolCallLocationsEqual(before.locations, after.locations) { return true }

        let beforeLast = before.content.last?.displayText
        let afterLast = after.content.last?.displayText
        if beforeLast != afterLast { return true }

        if !anyCodableEqual(before.rawInput, after.rawInput) { return true }
        if !anyCodableEqual(before.rawOutput, after.rawOutput) { return true }

        return false
    }

    private func toolCallLocationsEqual(_ lhs: [ToolLocation]?, _ rhs: [ToolLocation]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let left?, let right?):
            guard left.count == right.count else { return false }
            for (l, r) in zip(left, right) {
                if l.path != r.path { return false }
                if l.line != r.line { return false }
            }
            return true
        }
    }

    private func anyCodableEqual(_ lhs: AnyCodable?, _ rhs: AnyCodable?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let left?, let right?):
            return anyCodableSnapshot(left) == anyCodableSnapshot(right)
        }
    }

    private func anyCodableSnapshot(_ value: AnyCodable) -> String {
        let raw = value.value
        if let string = raw as? String { return "s:\(string)" }
        if let int = raw as? Int { return "i:\(int)" }
        if let double = raw as? Double { return "d:\(double)" }
        if let bool = raw as? Bool { return "b:\(bool)" }
        if raw is NSNull { return "null" }

        if JSONSerialization.isValidJSONObject(raw),
           let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return "j:\(json)"
        }

        return "d:\(String(describing: raw))"
    }
}
