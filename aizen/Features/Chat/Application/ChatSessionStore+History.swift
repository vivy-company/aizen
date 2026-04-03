//
//  ChatSessionStore+History.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import ACP
import CoreData
import Foundation
import os.log

@MainActor
extension ChatSessionStore {
    func loadHistoricalMessages() {
        guard let sessionId = session.id else {
            logger.warning("Cannot load historical messages: session has no ID")
            return
        }

        guard historicalMessages.isEmpty else { return }

        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "session.id == %@", sessionId as CVarArg)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = 200

        do {
            let fetchedMessages = try viewContext.fetch(fetchRequest)
            let chronologicalMessages = Array(fetchedMessages.reversed())

            var decodedMessages: [MessageItem] = []
            decodedMessages.reserveCapacity(chronologicalMessages.count)

            var orderedToolCalls: [ToolCall] = []
            var seenToolCallIds = Set<String>()

            for chatMessage in chronologicalMessages {
                guard let id = chatMessage.id,
                      let role = chatMessage.role,
                      let contentJSON = chatMessage.contentJSON else {
                    logger.warning("Skipping message: missing required fields")
                    continue
                }

                let messageRole: MessageRole
                switch role {
                case "user":
                    messageRole = .user
                case "agent", "assistant":
                    messageRole = .agent
                default:
                    logger.warning("Skipping message with unknown role: \(role)")
                    continue
                }

                let contentBlocks = parseContentBlocks(from: contentJSON)
                let content = contentBlocks.map { block in
                    switch block {
                    case .text(let text):
                        return text.text
                    default:
                        return ""
                    }
                }.joined()

                let records = ((chatMessage.toolCalls as? Set<ToolCallRecord>) ?? [])
                    .sorted { lhs, rhs in
                        let leftTimestamp = lhs.timestamp ?? .distantPast
                        let rightTimestamp = rhs.timestamp ?? .distantPast
                        if leftTimestamp != rightTimestamp {
                            return leftTimestamp < rightTimestamp
                        }
                        return (lhs.id ?? "") < (rhs.id ?? "")
                    }

                var messageToolCalls: [ToolCall] = []
                for record in records {
                    guard let call = decodeToolCall(from: record) else { continue }
                    messageToolCalls.append(call)

                    if seenToolCallIds.insert(call.id).inserted {
                        orderedToolCalls.append(call)
                    }
                }

                var messageItem = MessageItem(
                    id: id.uuidString,
                    role: messageRole,
                    content: content,
                    timestamp: chatMessage.timestamp ?? Date(),
                    contentBlocks: contentBlocks,
                    isComplete: true
                )
                messageItem.toolCalls = messageToolCalls
                decodedMessages.append(messageItem)
            }

            historicalMessages = decodedMessages
            historicalToolCalls = orderedToolCalls
        } catch {
            logger.error("Failed to fetch historical messages: \(error.localizedDescription)")
        }
    }

    func compactHistoryMarkdown() -> String? {
        let recentMessages = historicalMessages.suffix(30)
        let recentToolCalls = historicalToolCalls.suffix(40)

        guard !recentMessages.isEmpty || !recentToolCalls.isEmpty else { return nil }

        var lines: [String] = []
        lines.append("# Restored session context")
        lines.append("")
        lines.append("Summary of the previous session for context only.")

        if !recentMessages.isEmpty {
            lines.append("")
            lines.append("## Messages")
            for message in recentMessages {
                let role: String
                switch message.role {
                case .user: role = "User"
                case .agent: role = "Assistant"
                case .system: role = "System"
                }
                let text = compactHistoryText(message.content, limit: 600)
                if text.isEmpty { continue }
                lines.append("- **\(role)**: \(text)")
            }
        }

        if !recentToolCalls.isEmpty {
            lines.append("")
            lines.append("## Tool calls")
            for call in recentToolCalls {
                let title = compactHistoryText(call.title, limit: 160)
                let status = call.status.rawValue
                let kind = call.kind?.rawValue ?? "other"
                lines.append("- \(title) _(kind: \(kind), status: \(status))_")
            }
        }

        let result = lines.joined(separator: "\n")
        if result.count <= 12000 {
            return result
        }
        return String(result.prefix(12000)) + "\n…"
    }

    func hasHistoryAttachment() -> Bool {
        attachments.contains { attachment in
            if case .text(let content) = attachment {
                return content.hasPrefix("# Restored session context")
            }
            return false
        }
    }

    private func decodeToolCall(from record: ToolCallRecord) -> ToolCall? {
        let id = record.id ?? ""
        guard !id.isEmpty else { return nil }

        let title = record.title ?? ""
        let kind = ToolKind(rawValue: record.kind ?? "")
        let status = ToolStatus(rawValue: record.status ?? "") ?? .completed
        let timestamp = record.timestamp ?? Date()

        if let json = record.contentJSON,
           let data = json.data(using: .utf8) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(ToolCall.self, from: data) {
                return decoded
            }
            if let content = try? decoder.decode([ToolCallContent].self, from: data) {
                return ToolCall(
                    toolCallId: id,
                    title: title,
                    kind: kind,
                    status: status,
                    content: content,
                    locations: nil,
                    rawInput: nil,
                    rawOutput: nil,
                    timestamp: timestamp,
                    iterationId: nil,
                    parentToolCallId: nil
                )
            }
        }

        return ToolCall(
            toolCallId: id,
            title: title,
            kind: kind,
            status: status,
            content: [],
            locations: nil,
            rawInput: nil,
            rawOutput: nil,
            timestamp: timestamp,
            iterationId: nil,
            parentToolCallId: nil
        )
    }

    private func parseContentBlocks(from json: String) -> [ContentBlock] {
        guard let data = json.data(using: .utf8),
              let blocks = try? JSONDecoder().decode([ContentBlock].self, from: data) else {
            return [.text(TextContent(text: json))]
        }
        return blocks
    }

    private func compactHistoryText(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
