import ACP
import Foundation

extension ChatMessageList {
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

}
