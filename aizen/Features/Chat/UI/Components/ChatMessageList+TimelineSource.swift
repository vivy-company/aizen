import ACP
import Foundation

extension ChatMessageList {
    enum OrderedTimelineSource {
        case message(MessageItem)
        case toolCall(ToolCall)
    }

    struct OrderedTimelineItem {
        let source: OrderedTimelineSource
        let timestamp: Date
        let priority: Int
        let sequence: Int
    }

    func assembleTimelineSourceItems() -> [TimelineSourceItem] {
        let orderedSources = orderedTimelineSources()

        var items: [TimelineSourceItem] = []
        var toolCallBuffer: [ToolCall] = []
        var turnToolCalls: [ToolCall] = []
        var pendingSystemMessages: [MessageItem] = []

        for ordered in orderedSources {
            switch ordered.source {
            case .message(let message):
                if message.role == .system {
                    pendingSystemMessages.append(message)
                    continue
                }

                if message.role == .user {
                    if !toolCallBuffer.isEmpty {
                        appendBufferedToolCalls(toolCallBuffer, into: &items)
                        turnToolCalls.append(contentsOf: toolCallBuffer)
                        toolCallBuffer.removeAll(keepingCapacity: true)
                    }

                    if !turnToolCalls.isEmpty {
                        items.append(.turnSummary(makeTurnSummary(from: turnToolCalls)))
                        turnToolCalls.removeAll(keepingCapacity: true)
                    }

                    for systemMessage in pendingSystemMessages {
                        items.append(.message(systemMessage))
                    }
                    pendingSystemMessages.removeAll(keepingCapacity: true)
                }

                if message.role == .agent && !toolCallBuffer.isEmpty {
                    appendBufferedToolCalls(toolCallBuffer, into: &items)
                    turnToolCalls.append(contentsOf: toolCallBuffer)
                    toolCallBuffer.removeAll(keepingCapacity: true)
                }

                items.append(.message(message))

            case .toolCall(let toolCall):
                toolCallBuffer.append(toolCall)
            }
        }

        if !toolCallBuffer.isEmpty {
            turnToolCalls.append(contentsOf: toolCallBuffer)
            if isStreaming {
                appendStreamingToolCallItems(from: toolCallBuffer, into: &items)
            } else {
                appendBufferedToolCalls(toolCallBuffer, into: &items)
                items.append(.turnSummary(makeTurnSummary(from: turnToolCalls)))
                for systemMessage in pendingSystemMessages {
                    items.append(.message(systemMessage))
                }
                pendingSystemMessages.removeAll(keepingCapacity: true)
            }
        } else if !isStreaming && !turnToolCalls.isEmpty {
            items.append(.turnSummary(makeTurnSummary(from: turnToolCalls)))
            for systemMessage in pendingSystemMessages {
                items.append(.message(systemMessage))
            }
            pendingSystemMessages.removeAll(keepingCapacity: true)
        }

        if !pendingSystemMessages.isEmpty {
            for systemMessage in pendingSystemMessages {
                items.append(.message(systemMessage))
            }
        }

        return items
    }

    func orderedTimelineSources() -> [OrderedTimelineItem] {
        let anchoredTimestamps = anchoredToolCallTimestamps()
        var sequence = 0
        var items: [OrderedTimelineItem] = []
        items.reserveCapacity(messages.count + topLevelToolCalls.count)

        for message in messages {
            let source = OrderedTimelineSource.message(message)
            items.append(
                OrderedTimelineItem(
                    source: source,
                    timestamp: message.timestamp,
                    priority: sortPriority(for: source),
                    sequence: sequence
                )
            )
            sequence += 1
        }

        for toolCall in topLevelToolCalls {
            let source = OrderedTimelineSource.toolCall(toolCall)
            items.append(
                OrderedTimelineItem(
                    source: source,
                    timestamp: anchoredTimestamps[toolCall.id] ?? toolCall.timestamp,
                    priority: sortPriority(for: source),
                    sequence: sequence
                )
            )
            sequence += 1
        }

        items.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.sequence < rhs.sequence
        }

        return items
    }

    func anchoredToolCallTimestamps() -> [String: Date] {
        var anchoredByID: [String: Date] = [:]

        for message in messages {
            let messageToolCalls = message.toolCalls.filter { $0.parentToolCallId == nil }
            guard !messageToolCalls.isEmpty else { continue }

            for (index, toolCall) in messageToolCalls.enumerated() {
                let remaining = messageToolCalls.count - index
                let anchored = message.timestamp.addingTimeInterval(-Double(remaining) * 0.000_001)
                if let existing = anchoredByID[toolCall.id] {
                    if anchored < existing {
                        anchoredByID[toolCall.id] = anchored
                    }
                } else {
                    anchoredByID[toolCall.id] = anchored
                }
            }
        }

        return anchoredByID
    }

    func sortPriority(for source: OrderedTimelineSource) -> Int {
        switch source {
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

    func appendBufferedToolCalls(_ toolCalls: [ToolCall], into items: inout [TimelineSourceItem]) {
        guard !toolCalls.isEmpty else { return }

        if toolCalls.count == 1, let toolCall = toolCalls.first {
            items.append(.toolCall(toolCall))
            return
        }

        items.append(.toolCallGroup(makeToolCallGroup(from: toolCalls)))
    }

    func appendStreamingToolCallItems(from toolCalls: [ToolCall], into items: inout [TimelineSourceItem]) {
        var explorationBuffer: [ToolCall] = []

        func flushExplorationBuffer() {
            guard !explorationBuffer.isEmpty else { return }
            items.append(.toolCallGroup(makeToolCallGroup(from: explorationBuffer)))
            explorationBuffer.removeAll(keepingCapacity: true)
        }

        for toolCall in toolCalls {
            if isExplorationCandidate(toolCall) {
                explorationBuffer.append(toolCall)
                continue
            }

            flushExplorationBuffer()
            items.append(.toolCall(toolCall))
        }

        flushExplorationBuffer()
    }

    func makeToolCallGroup(from toolCalls: [ToolCall]) -> ToolCallGroup {
        ToolCallGroup(toolCalls: toolCalls)
    }

    func makeTurnSummary(from toolCalls: [ToolCall]) -> TurnSummary {
        let timestamps = toolCalls.map(\.timestamp)
        let start = timestamps.min() ?? Date()
        let end = timestamps.max() ?? Date()
        let duration = end.timeIntervalSince(start)
        let key = toolCalls.map(\.id).joined(separator: "|")
        let id = key.isEmpty ? UUID().uuidString : key

        return TurnSummary(
            id: id,
            timestamp: end,
            duration: duration,
            toolCallCount: toolCalls.count,
            fileChanges: turnSummaryFileChanges(from: toolCalls)
        )
    }

    func turnSummaryFileChanges(from toolCalls: [ToolCall]) -> [FileChangeSummary] {
        var changes: [String: FileChangeSummary] = [:]

        for toolCall in toolCalls where toolCall.kind == .some(.edit) {
            let filePath: String?
            if let path = toolCall.locations?.first?.path {
                filePath = path
            } else if !toolCall.title.isEmpty && toolCall.title.contains("/") {
                filePath = toolCall.title
            } else {
                filePath = nil
            }

            guard let filePath else { continue }

            var linesAdded = 0
            var linesRemoved = 0
            var isNewFile = false

            for content in toolCall.content {
                guard case .diff(let diff) = content else { continue }

                isNewFile = diff.oldText == nil || diff.oldText?.isEmpty == true
                let delta = diffLineDelta(oldText: diff.oldText, newText: diff.newText)
                linesAdded += delta.added
                linesRemoved += delta.removed
            }

            if let existing = changes[filePath] {
                changes[filePath] = FileChangeSummary(
                    path: filePath,
                    isNew: existing.isNew || isNewFile,
                    linesAdded: existing.linesAdded + linesAdded,
                    linesRemoved: existing.linesRemoved + linesRemoved
                )
            } else {
                changes[filePath] = FileChangeSummary(
                    path: filePath,
                    isNew: isNewFile,
                    linesAdded: linesAdded,
                    linesRemoved: linesRemoved
                )
            }
        }

        return changes.values.sorted { $0.path < $1.path }
    }

    func isExplorationCandidate(_ toolCall: ToolCall) -> Bool {
        if let kind = toolCall.kind {
            let rawValue = kind.rawValue.lowercased()
            if rawValue == "read" || rawValue == "search" || rawValue == "grep" || rawValue == "list" {
                return true
            }
            if kind == .execute && hasListIntent(toolCall) {
                return true
            }
        }

        return hasListIntent(toolCall)
    }

    func hasListIntent(_ toolCall: ToolCall) -> Bool {
        let normalizedTitle = toolCall.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedTitle.hasPrefix("list ") || normalizedTitle == "list" {
            return true
        }

        if let rawInput = toolCall.rawInput?.value as? [String: Any] {
            if let command = rawInput["command"] as? String, isListCommand(command) {
                return true
            }
            if let cmd = rawInput["cmd"] as? String, isListCommand(cmd) {
                return true
            }
            if let args = rawInput["args"] as? [String], isListCommand(args.joined(separator: " ")) {
                return true
            }
        }

        return false
    }

    func isListCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }

        let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if ["ls", "find", "fd", "tree", "dir", "rg", "ripgrep", "grep", "glob"].contains(firstToken) {
            return true
        }

        return trimmed.contains(" --files") || trimmed.hasPrefix("list ")
    }
}
