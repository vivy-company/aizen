//
//  ChatAgentSessionNotifications.swift
//  aizen
//
//  Notification handling logic for ChatAgentSession
//

import ACP
import Foundation
import Combine

// MARK: - ChatAgentSession + Notifications

@MainActor
extension ChatAgentSession {
    /// Start listening for notifications from the ACP client
    func startNotificationListener(client: Client) {
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

        notificationProcessingTask = Task { @MainActor [weak self] in
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
            }
        }
    }

    /// Process session update
    private func processUpdate(_ update: SessionUpdate) {
        if suppressResumedAgentMessages {
            switch update {
            case .toolCall, .toolCallUpdate:
                return
            default:
                break
            }
        }

        switch update {
            case .toolCall(let toolCallUpdate):
                // Mark any in-progress agent message as complete before tool execution
                markLastMessageComplete()

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
                handleAgentMessageChunk(block)
            case .userMessageChunk:
                break
            case .agentThoughtChunk(let block):
                handleAgentThoughtChunk(block)
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
                availableConfigOptions = configOptions
                if configOptions.isEmpty {
                } else {
                }
            case .sessionInfoUpdate:
                break
            case .usageUpdate:
                break
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

    func coalesceAdjacentTextBlocks(_ blocks: [ToolCallContent]) -> [ToolCallContent] {
        var result: [ToolCallContent] = []
        var seenDiffPaths = Set<String>()

        for block in blocks {
            // Deduplicate diff blocks by path (keep first occurrence)
            if case .diff(let diff) = block {
                if seenDiffPaths.contains(diff.path) {
                    continue
                }
                seenDiffPaths.insert(diff.path)
                result.append(block)
                continue
            }

            // Coalesce adjacent text blocks
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
    func textAndContent(from block: ContentBlock) -> (String, [ContentBlock]) {
        switch block {
        case .text(let text):
            return (text.text, [.text(text)])
        default:
            return ("", [block])
        }
    }

    private func handleNotificationStreamEnded() {
        if isStreaming {
            isStreaming = false
        }
        resetFinalizeState()
        markLastMessageComplete()
        clearThoughtBuffer()
        currentThought = nil
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
