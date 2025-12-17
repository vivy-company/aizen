//
//  AgentSessionNotifications.swift
//  aizen
//
//  Notification handling logic for AgentSession
//

import Foundation
import os.log

// MARK: - AgentSession + Notifications

@MainActor
extension AgentSession {
    /// Start listening for notifications from the ACP client
    func startNotificationListener(client: ACPClient) {
        notificationTask = Task { @MainActor in
            for await notification in await client.notifications {
                handleNotification(notification)
            }
        }
    }

    /// Handle incoming session update notifications
    func handleNotification(_ notification: JSONRPCNotification) {
        guard notification.method == "session/update" else {
            return
        }

        logger.debug("session/update raw params: \(String(describing: notification.params?.value))")

        do {
            let params = notification.params?.value as? [String: Any] ?? [:]
            let data = try JSONSerialization.data(withJSONObject: params)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let updateNotification = try decoder.decode(SessionUpdateNotification.self, from: data)

            logger.debug("Parsed session/update: \(String(describing: updateNotification.update))")

            // Handle different update types using the strongly-typed enum
            switch updateNotification.update {
            case .toolCall(let toolCallUpdate):
                // Check if this is a Task (subagent) tool call
                let isTaskTool = isTaskToolCall(toolCallUpdate)

                // Determine parent for non-Task tool calls
                // Only assign parent when exactly one Task is active (sequential execution)
                // For parallel Tasks, we cannot reliably determine which Task spawned which tool
                var parentId: String? = nil
                if !isTaskTool && activeTaskIds.count == 1 {
                    parentId = activeTaskIds.first
                }

                // Track active Tasks
                if isTaskTool && toolCallUpdate.status == .pending {
                    activeTaskIds.append(toolCallUpdate.toolCallId)
                }

                // Prefer full payload when provided; use readable title fallback
                let preferredTitle = normalizedTitle(toolCallUpdate.title) ?? derivedTitle(from: toolCallUpdate)
                var toolCall = toolCallUpdate.asToolCall(
                    preferredTitle: preferredTitle,
                    iterationId: currentIterationId,
                    fallbackTitle: { self.fallbackTitle(kind: $0) }
                )
                toolCall.parentToolCallId = parentId
                updateToolCalls([toolCall])
            case .toolCallUpdate(let details):
                let toolCallId = details.toolCallId
                // O(1) dictionary lookup instead of O(n) array search
                updateToolCallInPlace(id: toolCallId) { updated in
                    updated.status = details.status ?? updated.status
                    updated.locations = details.locations ?? updated.locations
                    updated.kind = details.kind ?? updated.kind
                    updated.rawInput = details.rawInput ?? updated.rawInput
                    updated.rawOutput = details.rawOutput ?? updated.rawOutput
                    if let newTitle = normalizedTitle(details.title) {
                        updated.title = newTitle
                    }
                    if let newContent = details.content {
                        let merged = coalesceAdjacentTextBlocks(updated.content + newContent)
                        updated.content = merged
                    }
                }

                // Clean up activeTaskIds when Task completes
                if details.status == .completed || details.status == .failed {
                    activeTaskIds.removeAll { $0 == toolCallId }
                }
            case .agentMessageChunk(let block):
                currentThought = nil
                let (text, blockContent) = textAndContent(from: block)
                guard !text.isEmpty else { break }

                if let lastMessage = messages.last,
                   lastMessage.role == .agent,
                   !lastMessage.isComplete {
                    // Create new struct with appended content
                    let newContent = lastMessage.content + text
                    messages[messages.count - 1] = MessageItem(
                        id: lastMessage.id,
                        role: .agent,
                        content: newContent,
                        timestamp: lastMessage.timestamp,
                        toolCalls: lastMessage.toolCalls,
                        contentBlocks: lastMessage.contentBlocks + blockContent,
                        isComplete: false,
                        startTime: lastMessage.startTime,
                        executionTime: lastMessage.executionTime,
                        requestId: lastMessage.requestId
                    )
                } else {
                    addAgentMessage(text, contentBlocks: blockContent, isComplete: false, startTime: Date())
                }
            case .userMessageChunk:
                break
            case .agentThoughtChunk(let block):
                let (text, _) = textAndContent(from: block)
                if text.isEmpty { break }
                logger.debug("Agent thought: \(text)")
                if let existing = currentThought {
                    currentThought = existing + text
                } else {
                    currentThought = text
                }
            case .plan(let plan):
                agentPlan = plan
            case .availableCommandsUpdate(let commands):
                availableCommands = commands
            case .currentModeUpdate(let mode):
                currentModeId = mode
                currentMode = SessionMode(rawValue: mode)
            }
        } catch {
            logger.error("Failed to parse session update: \(error.localizedDescription)")
            self.error = "Failed to parse session update: \(error.localizedDescription)"
        }
    }

    /// Update tool calls with new information (O(1) dictionary operations)
    func updateToolCalls(_ newToolCalls: [ToolCall]) {
        for newCall in newToolCalls {
            let id = newCall.toolCallId
            if let existing = getToolCall(id: id) {
                // Merge content instead of replacing entirely
                let mergedContent = coalesceAdjacentTextBlocks(existing.content + newCall.content)
                var updated = ToolCall(
                    toolCallId: id,
                    title: cleanTitle(newCall.title).isEmpty ? existing.title : cleanTitle(newCall.title),
                    kind: newCall.kind,
                    status: newCall.status,
                    content: mergedContent,
                    locations: newCall.locations ?? existing.locations,
                    rawInput: newCall.rawInput ?? existing.rawInput,
                    rawOutput: newCall.rawOutput ?? existing.rawOutput,
                    timestamp: existing.timestamp
                )
                updated.iterationId = existing.iterationId
                updated.parentToolCallId = existing.parentToolCallId ?? newCall.parentToolCallId
                upsertToolCall(updated)
            } else {
                // New tool call - add to dictionary and order
                upsertToolCall(newCall)
            }
        }
    }

    // MARK: - Content Decoding

    
    private func decodeContentBlocks(_ content: AnyCodable?) -> [ContentBlock] {
        guard let value = content?.value else { return [] }

        // 1) simple shapes
        if let string = value as? String {
            return [.text(TextContent(text: string))]
        }

        if let strings = value as? [String] {
            return [.text(TextContent(text: strings.joined(separator: "\n")))]
        }

        // 2) try direct decode of standard content blocks
        if let array = value as? [[String: Any]] {
            do {
                let data = try JSONSerialization.data(withJSONObject: array)
                return try JSONDecoder().decode([ContentBlock].self, from: data)
            } catch {
                // Attempt to unwrap MCP-style {"type":"content","content":{...}}
                let flattened = array.compactMap { dict -> String? in
                    if let inner = dict["content"] as? [String: Any] {
                        return extractText(inner["text"])
                    }
                    return extractText(dict["text"])
                }
                if !flattened.isEmpty {
                    return [.text(TextContent(text: flattened.joined()))]
                }
                logger.debug("Tool call content decode failed: \(error.localizedDescription); raw=\(array)")
            }
        }

        // 3) single dict
        if let dict = value as? [String: Any] {
            if let text = extractText(dict["text"]) {
                return [.text(TextContent(text: text))]
            }
            if let inner = dict["content"] as? [String: Any], let text = extractText(inner["text"]) {
                return [.text(TextContent(text: text))]
            }
        }

        // last resort
        logger.debug("Tool call content decode failed: unhandled shape raw=\(String(describing: value))")
        return []
    }

    /// Merge adjacent text blocks to avoid fragment spam from streamed chunks
    private func coalesceAdjacentTextBlocks(_ blocks: [ContentBlock]) -> [ContentBlock] {
        var result: [ContentBlock] = []

        for block in blocks {
            if case .text(let newText) = block, let last = result.last, case .text(let lastText) = last {
                // Skip exact duplicates
                if lastText.text == newText.text {
                    continue
                }
                // Replace last with combined text
                result.removeLast()
                let combined = TextContent(text: lastText.text + newText.text)
                result.append(.text(combined))
            } else {
                result.append(block)
            }
        }
        return result
    }

    private func coalesceAdjacentTextBlocks(_ blocks: [ToolCallContent]) -> [ToolCallContent] {
        var result: [ToolCallContent] = []

        for block in blocks {
            if case .content(let contentBlock) = block,
               case .text(let newText) = contentBlock,
               let last = result.last,
               case .content(let lastContentBlock) = last,
               case .text(let lastText) = lastContentBlock {
                // Skip exact duplicates
                if lastText.text == newText.text {
                    continue
                }
                // Replace last with combined text
                result.removeLast()
                let combined = TextContent(text: lastText.text + newText.text)
                result.append(.content(.text(combined)))
            } else {
                result.append(block)
            }
        }
        return result
    }

    /// Extract plain text from a content block (best effort)
    private func textAndContent(from block: ContentBlock) -> (String, [ContentBlock]) {
        switch block {
        case .text(let text):
            return (text.text, [.text(text)])
        default:
            return ("", [block])
        }
    }

    private func normalizedTitle(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func fallbackTitle(kind: ToolKind?) -> String {
        guard let kind else { return "Tool" }
        let text = kind.rawValue.replacingOccurrences(of: "_", with: " ")
        return text.capitalized
    }

    /// Best-effort human title from tool input payloads
    private func derivedTitle(from update: ToolCallUpdate) -> String? {
        guard let raw = update.rawInput?.value as? [String: Any] else { return nil }

        // Common keys agents send
        let keys = ["path", "file", "filePath", "query", "command", "title", "name", "description"]
        for key in keys {
            if let val = raw[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val
            }
        }

        // If args array exists, join for display
        if let args = raw["args"] as? [String], !args.isEmpty {
            return args.joined(separator: " ")
        }

        return nil
    }

    private func cleanTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detect if a tool call is a Task (subagent) via _meta.claudeCode.toolName
    private func isTaskToolCall(_ update: ToolCallUpdate) -> Bool {
        guard let meta = update._meta,
              let claudeCode = meta["claudeCode"]?.value as? [String: Any],
              let toolName = claudeCode["toolName"] as? String else {
            return false
        }
        return toolName == "Task"
    }

    /// Extract best-effort string from loosely-typed "text" payloads
    private func extractText(_ raw: Any?) -> String? {
        guard let raw else { return nil }

        if let str = raw as? String { return str }

        if let dict = raw as? [String: Any] {
            // Prefer common output keys
            let preferredKeys = ["stdout", "stderr", "output", "text", "message", "result"]
            for key in preferredKeys {
                if let val = dict[key] as? String {
                    return val
                }
            }
            // Fallback: pretty-print JSON
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }

        if let array = raw as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return String(describing: raw)
    }

}

private extension ToolCallUpdate {
    func asToolCall(
        preferredTitle: String? = nil,
        iterationId: String? = nil,
        fallbackTitle: (ToolKind?) -> String = { kind in
            let text = kind?.rawValue.replacingOccurrences(of: "_", with: " ") ?? "Tool"
            return text.capitalized
        }
    ) -> ToolCall {
        var call = ToolCall(
            toolCallId: toolCallId,
            title: preferredTitle ?? fallbackTitle(kind),
            kind: kind,
            status: status,
            content: content,
            locations: locations,
            rawInput: rawInput,
            rawOutput: rawOutput,
            timestamp: Date()
        )
        call.iterationId = iterationId
        return call
    }
}
