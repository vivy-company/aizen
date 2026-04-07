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
}
