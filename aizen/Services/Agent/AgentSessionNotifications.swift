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

        do {
            let params = notification.params?.value as? [String: Any]
            let data = try JSONSerialization.data(withJSONObject: params ?? [:])
            let updateNotification = try JSONDecoder().decode(SessionUpdateNotification.self, from: data)

            let updateType = updateNotification.update.sessionUpdate

            // Handle different update types
            switch updateType {
            case "tool_call", "tool_call_update":
                // Prefer full payload when provided
                if let toolCallsPayload = updateNotification.update.toolCalls, !toolCallsPayload.isEmpty {
                    updateToolCalls(toolCallsPayload)
                    break
                }

                // Fallback to single-field updates
                if let toolCallId = updateNotification.update.toolCallId {
                    // If this is a new tool call (not an update), mark current message complete
                    if updateNotification.update.sessionUpdate == "tool_call" &&
                       !toolCalls.contains(where: { $0.toolCallId == toolCallId }) {
                        markLastMessageComplete()
                    }

                    if let existingIndex = toolCalls.firstIndex(where: { $0.toolCallId == toolCallId }) {
                        // Update existing tool call with new fields/content
                        var updated = toolCalls[existingIndex]
                        let newBlocks = decodeContentBlocks(updateNotification.update.content)
                        let mergedContent = coalesceAdjacentTextBlocks(updated.content + newBlocks)

                        updated = ToolCall(
                            toolCallId: updated.toolCallId,
                            title: updateNotification.update.title ?? updated.title,
                            kind: updateNotification.update.kind ?? updated.kind,
                            status: updateNotification.update.status ?? updated.status,
                            content: mergedContent,
                            locations: updateNotification.update.locations ?? updated.locations,
                            rawInput: updateNotification.update.rawInput ?? updated.rawInput,
                            rawOutput: updateNotification.update.rawOutput ?? updated.rawOutput,
                            timestamp: updated.timestamp
                        )

                        toolCalls[existingIndex] = updated
                    } else {
                        // Create minimal placeholder so it shows up in UI even if some fields missing
                        let newCall = ToolCall(
                            toolCallId: toolCallId,
                            title: updateNotification.update.title ?? "Tool call",
                            kind: updateNotification.update.kind ?? .other,
                            status: updateNotification.update.status ?? .pending,
                            content: coalesceAdjacentTextBlocks(decodeContentBlocks(updateNotification.update.content)),
                            locations: updateNotification.update.locations,
                            rawInput: updateNotification.update.rawInput,
                            rawOutput: updateNotification.update.rawOutput,
                            timestamp: Date()
                        )
                        toolCalls.append(newCall)
                    }
                }

            case "agent_message_chunk":
                if let contentAny = updateNotification.update.content?.value {
                    currentThought = nil

                    if let contentDict = contentAny as? [String: Any],
                       let type = contentDict["type"] as? String,
                       type == "text",
                       let text = contentDict["text"] as? String {

                        // Append to last agent message if it exists and is still being streamed
                        if let lastMessage = messages.last,
                           lastMessage.role == .agent,
                           !lastMessage.isComplete {
                            let newContent = lastMessage.content + text
                            messages[messages.count - 1] = MessageItem(
                                id: lastMessage.id,
                                role: .agent,
                                content: newContent,
                                timestamp: lastMessage.timestamp,
                                toolCalls: lastMessage.toolCalls,
                                contentBlocks: lastMessage.contentBlocks,
                                isComplete: false,
                                startTime: lastMessage.startTime,
                                executionTime: lastMessage.executionTime,
                                requestId: lastMessage.requestId
                            )
                        } else {
                            // Start a new agent message
                            addAgentMessage(text, isComplete: false, startTime: Date())
                        }

                    }
                }

            case "user_message_chunk":
                // User messages already added when sending
                break

            case "agent_thought_chunk":
                if let contentAny = updateNotification.update.content?.value,
                   let contentDict = contentAny as? [String: Any],
                   let text = contentDict["text"] as? String {
                    logger.debug("Agent thought: \(text)")
                    // Accumulate thought chunks instead of replacing
                    if let existing = currentThought {
                        currentThought = existing + text
                    } else {
                        currentThought = text
                    }
                }

            case "plan":
                if let plan = updateNotification.update.plan {
                    agentPlan = plan
                }

            case "available_commands_update":
                if let commands = updateNotification.update.availableCommands {
                    availableCommands = commands
                }

            case "current_mode_update":
                if let mode = updateNotification.update.currentMode {
                    currentMode = mode
                }

            default:
                break
            }
        } catch {
            self.error = "Failed to parse session update: \(error.localizedDescription)"
        }
    }

    /// Update tool calls with new information
    func updateToolCalls(_ newToolCalls: [ToolCall]) {
        for newCall in newToolCalls {
            if let index = toolCalls.firstIndex(where: { $0.toolCallId == newCall.toolCallId }) {
                // Merge content instead of replacing entirely
                let existingContent = toolCalls[index].content
                let mergedContent = coalesceAdjacentTextBlocks(existingContent + newCall.content)
                toolCalls[index] = ToolCall(
                    toolCallId: newCall.toolCallId,
                    title: newCall.title.isEmpty ? toolCalls[index].title : newCall.title,
                    kind: newCall.kind,
                    status: newCall.status,
                    content: mergedContent,
                    locations: newCall.locations ?? toolCalls[index].locations,
                    rawInput: newCall.rawInput ?? toolCalls[index].rawInput,
                    rawOutput: newCall.rawOutput ?? toolCalls[index].rawOutput,
                    timestamp: toolCalls[index].timestamp
                )
            } else {
                toolCalls.append(newCall)
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
