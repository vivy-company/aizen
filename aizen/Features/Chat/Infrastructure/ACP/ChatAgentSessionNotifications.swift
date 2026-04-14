//
//  ChatAgentSessionNotifications.swift
//  aizen
//
//  Notification handling logic for ChatAgentSession
//

import ACP
import Foundation
import Combine
import os.log

// MARK: - ChatAgentSession + Notifications

@MainActor
extension ChatAgentSession {
    /// Start listening for notifications from the ACP client
    func startNotificationListener(client: Client) {
        notificationTask = Task { @MainActor in
            for await notification in await client.notifications {
                handleNotification(notification)
            }
            guard !Task.isCancelled else {
                return
            }
            handleNotificationStreamEnded()
        }
    }

    /// Handle incoming session update notifications
    func handleNotification(_ notification: JSONRPCNotification) {
        let previousTask = notificationProcessingTask

        notificationProcessingTask = Task { @MainActor [weak self] in
            if let previousTask {
                await previousTask.value
            }

            guard !Task.isCancelled else {
                return
            }

            do {
                let updateNotification = try await Task.detached(priority: .userInitiated) { () throws -> SessionUpdateNotification? in
                    try Self.decodeSessionUpdateNotification(from: notification)
                }.value

                guard let updateNotification else {
                    return
                }
                self?.processUpdate(updateNotification.update)
            } catch {
                Logger.acp.error("Failed to decode ACP session/update notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func decodeSessionUpdateNotification(
        from notification: JSONRPCNotification
    ) throws -> SessionUpdateNotification? {
        guard notification.method == "session/update" else {
            return nil
        }

        let params = notification.params?.value as? [String: Any] ?? [:]
        let data = try JSONSerialization.data(withJSONObject: params)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SessionUpdateNotification.self, from: data)
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
