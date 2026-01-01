//
//  AgentSessionNotifications.swift
//  aizen
//
//  Notification handling logic for AgentSession
//

import Foundation
import Combine
import os

// MARK: - AgentSession + Notifications

@MainActor
extension AgentSession {
    /// Start listening for notifications from the ACP client
    func startNotificationListener(client: ACPClient) {
        notificationTask = Task { @MainActor in
            for await notification in await client.notifications {
                handleNotification(notification)
            }
            handleNotificationStreamEnded()
        }
    }

    /// Handle incoming session update notifications
    func handleNotification(_ notification: JSONRPCNotification) {
        guard notification.method == "session/update" else {
            return
        }

        let params = notification.params?.value as? [String: Any] ?? [:]

        let previousTask = notificationProcessingTask
        let logger = self.logger
        let rawParams = notification.params

        notificationProcessingTask = Task(priority: .userInitiated) { [weak self] in
            if let previousTask {
                await previousTask.value
            }

            do {
                let data = try JSONSerialization.data(withJSONObject: params)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let updateNotification = try decoder.decode(SessionUpdateNotification.self, from: data)

                self?.processUpdate(updateNotification.update)
            } catch {
                logger.warning("Failed to parse session update: \(error.localizedDescription)\nRaw params: \(String(describing: rawParams))")
            }
        }
    }

    /// Process session update
    private func processUpdate(_ update: SessionUpdate) {
        switch update {
            case .toolCall(let toolCallUpdate):
                // Mark any in-progress agent message as complete before tool execution
                markLastMessageComplete()

                // Handle terminal_info meta (experimental Claude Code feature)
                if let meta = toolCallUpdate._meta,
                   let terminalInfo = meta["terminal_info"]?.value as? [String: Any],
                   let terminalIdStr = terminalInfo["terminal_id"] as? String {
                    // Terminal output will be streamed via terminal_output meta in ToolCallUpdate
                    logger.debug("Tool call \(toolCallUpdate.toolCallId) has associated terminal: \(terminalIdStr)")
                }

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
                applyBufferedToolCallUpdatesIfPresent(for: toolCallUpdate.toolCallId)
            case .toolCallUpdate(let details):
                let toolCallId = details.toolCallId
                let isTaskTool = isTaskToolCall(details)
                let status = details.status ?? .pending

                if isTaskTool && status == .pending {
                    if !activeTaskIds.contains(toolCallId) {
                        activeTaskIds.append(toolCallId)
                    }
                }

                if getToolCall(id: toolCallId) == nil {
                    if ensureToolCallExists(from: details, isTaskTool: isTaskTool) {
                        applyBufferedToolCallUpdatesIfPresent(for: toolCallId)
                    } else {
                        bufferToolCallUpdate(details)
                        return
                    }
                }

                // Single update combining all changes (avoids state corruption)
                updateToolCallInPlace(id: toolCallId) { updated in
                    applyToolCallUpdate(details, to: &updated)
                }

                // Clean up activeTaskIds when Task completes
                if details.status == .completed || details.status == .failed {
                    activeTaskIds.removeAll { $0 == toolCallId }
                }
            case .agentMessageChunk(let block):
                clearThoughtBuffer()
                currentThought = nil
                let (text, blockContent) = textAndContent(from: block)
                if text.isEmpty && blockContent.isEmpty { break }
                recordAgentChunk()

                // Find the last agent message (not just last message)
                // This prevents system messages (like mode changes) from splitting the stream
                let lastAgentMessage = messages.last { $0.role == .agent }

                if let lastAgentMessage = lastAgentMessage,
                   !lastAgentMessage.isComplete {
                    // Append to existing incomplete agent message (buffered to reduce UI churn)
                    appendAgentMessageChunk(text: text, contentBlocks: blockContent)
                } else {
                    let initialText = text
                    let initialBlocks = blockContent
                    AgentUsageStore.shared.recordAgentMessage(agentId: agentName)
                    clearAgentMessageBuffer()
                    addAgentMessage(initialText, contentBlocks: initialBlocks, isComplete: false, startTime: Date())
                }
            case .userMessageChunk:
                break
            case .agentThoughtChunk(let block):
                let (text, _) = textAndContent(from: block)
                if text.isEmpty { break }
                appendThoughtChunk(text)
            case .plan(let plan):
                // Coalesce plan updates - only update if content changed
                // This prevents excessive UI rebuilds when multiple agents stream plan updates
                if agentPlan != plan {
                    agentPlan = plan
                }
            case .availableCommandsUpdate(let commands):
                availableCommands = commands
            case .currentModeUpdate(let mode):
                currentModeId = mode
                currentMode = SessionMode(rawValue: mode)
            case .configOptionUpdate(let configOptions):
                // Store config options for UI rendering
                // Config options take precedence over legacy modes/models
                if !configOptions.isEmpty {
                    // TODO: Update UI to display config options
                    // For now, just log them
                    logger.info("Config options updated: \(configOptions.count) options")
                }
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
                AgentUsageStore.shared.recordToolCall(agentId: agentName)
                upsertToolCall(newCall)
            }
        }
    }

    // MARK: - Content Decoding
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
        isTaskToolCall(update._meta)
    }

    private func isTaskToolCall(_ details: ToolCallUpdateDetails) -> Bool {
        isTaskToolCall(details._meta)
    }

    private func isTaskToolCall(_ meta: [String: AnyCodable]?) -> Bool {
        guard let meta,
              let claudeCode = meta["claudeCode"]?.value as? [String: Any],
              let toolName = claudeCode["toolName"] as? String else {
            return false
        }
        return toolName == "Task"
    }

    private func handleNotificationStreamEnded() {
        logger.warning("Notification stream ended; finalizing current turn")
        if isStreaming {
            isStreaming = false
        }
        resetFinalizeState()
        markLastMessageComplete()
        clearThoughtBuffer()
        currentThought = nil
    }

    private func bufferToolCallUpdate(_ details: ToolCallUpdateDetails) {
        pendingToolCallUpdatesById[details.toolCallId, default: []].append(details)
    }

    private func bufferToolCallContent(_ content: [ToolCallContent], for toolCallId: String) {
        guard !content.isEmpty else { return }
        pendingToolCallContentById[toolCallId, default: []].append(contentsOf: content)
        scheduleToolCallContentFlush(for: toolCallId)
    }

    private func scheduleToolCallContentFlush(for toolCallId: String) {
        guard toolCallContentFlushTasks[toolCallId] == nil else { return }
        toolCallContentFlushTasks[toolCallId] = Task { @MainActor in
            defer { toolCallContentFlushTasks[toolCallId] = nil }
            try? await Task.sleep(for: .seconds(Self.toolCallContentFlushInterval))
            flushToolCallContent(for: toolCallId)
        }
    }

    private func flushToolCallContent(for toolCallId: String) {
        guard let pending = pendingToolCallContentById.removeValue(forKey: toolCallId),
              !pending.isEmpty else {
            return
        }
        toolCallContentFlushTasks[toolCallId]?.cancel()
        toolCallContentFlushTasks[toolCallId] = nil

        updateToolCallInPlace(id: toolCallId) { updated in
            var allContent = updated.content
            allContent.append(contentsOf: pending)
            updated.content = coalesceAdjacentTextBlocks(allContent)
        }
    }

    private func applyBufferedToolCallUpdatesIfPresent(for toolCallId: String) {
        guard let pending = pendingToolCallUpdatesById.removeValue(forKey: toolCallId),
              !pending.isEmpty else {
            return
        }

        updateToolCallInPlace(id: toolCallId) { updated in
            for details in pending {
                applyToolCallUpdate(details, to: &updated)
            }
        }
    }

    private func ensureToolCallExists(from details: ToolCallUpdateDetails, isTaskTool: Bool) -> Bool {
        guard getToolCall(id: details.toolCallId) == nil else { return true }
        guard let title = normalizedTitle(details.title) else { return false }

        var parentId: String? = nil
        if !isTaskTool && activeTaskIds.count == 1 {
            parentId = activeTaskIds.first
        }

        var toolCall = ToolCall(
            toolCallId: details.toolCallId,
            title: title,
            kind: details.kind,
            status: details.status ?? .pending,
            content: [],
            locations: details.locations,
            rawInput: details.rawInput,
            rawOutput: details.rawOutput,
            timestamp: Date()
        )
        toolCall.iterationId = currentIterationId
        toolCall.parentToolCallId = parentId
        updateToolCalls([toolCall])
        return true
    }

    private func applyToolCallUpdate(_ details: ToolCallUpdateDetails, to updated: inout ToolCall) {
        // Extract terminal meta fields if present (experimental Claude Code feature)
        var terminalOutputContent: [ToolCallContent] = []
        if let meta = details._meta {
            // Handle terminal_output meta
            if let terminalOutput = meta["terminal_output"]?.value as? [String: Any],
               let outputData = terminalOutput["data"] as? String {
                let terminalContent = ToolCallContent.content(.text(TextContent(text: outputData)))
                terminalOutputContent.append(terminalContent)
            }

            // Handle terminal_exit meta
            if let terminalExit = meta["terminal_exit"]?.value as? [String: Any] {
                let exitCode = terminalExit["exit_code"] as? Int
                let signal = terminalExit["signal"] as? String
                let exitMessage = if let code = exitCode {
                    "Terminal exited with code \(code)"
                } else if let sig = signal {
                    "Terminal terminated by signal \(sig)"
                } else {
                    "Terminal exited"
                }
                let exitContent = ToolCallContent.content(.text(TextContent(text: "\n\(exitMessage)\n")))
                terminalOutputContent.append(exitContent)
            }
        }

        updated.status = details.status ?? updated.status
        updated.locations = details.locations ?? updated.locations
        updated.kind = details.kind ?? updated.kind
        updated.rawInput = details.rawInput ?? updated.rawInput
        updated.rawOutput = details.rawOutput ?? updated.rawOutput
        if let newTitle = normalizedTitle(details.title) {
            updated.title = newTitle
        }

        // Merge content with buffering to reduce heavy updates (especially for large file reads)
        var incomingContent = terminalOutputContent
        if let newContent = details.content, !newContent.isEmpty {
            incomingContent.append(contentsOf: newContent)
        }

        let status = details.status ?? updated.status
        if !incomingContent.isEmpty {
            let shouldFlushNow = status == .completed || status == .failed
            if shouldFlushNow {
                flushToolCallContent(for: details.toolCallId)
                var allContent = updated.content
                allContent.append(contentsOf: incomingContent)
                updated.content = coalesceAdjacentTextBlocks(allContent)
            } else {
                bufferToolCallContent(incomingContent, for: details.toolCallId)
            }
        } else if status == .completed || status == .failed {
            flushToolCallContent(for: details.toolCallId)
        }
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
