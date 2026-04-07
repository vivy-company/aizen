//
//  ChatAgentSession+ToolCallNotifications.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    /// Update tool calls with new information (O(1) dictionary operations)
    func updateToolCalls(_ newToolCalls: [ToolCall]) {
        for newCall in newToolCalls {
            let id = newCall.toolCallId
            if let existing = getToolCall(id: id) {
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
                AgentUsageStore.shared.recordToolCall(agentId: agentName)
                upsertToolCall(newCall)
            }
        }
    }

    func normalizedTitle(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    func fallbackTitle(kind: ToolKind?) -> String {
        guard let kind else { return "Tool" }
        let text = kind.rawValue.replacingOccurrences(of: "_", with: " ")
        return text.capitalized
    }

    func derivedTitle(from update: ToolCallUpdate) -> String? {
        guard let raw = update.rawInput?.value as? [String: Any] else { return nil }

        let keys = ["path", "file", "filePath", "query", "command", "title", "name", "description"]
        for key in keys {
            if let val = raw[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val
            }
        }

        if let args = raw["args"] as? [String], !args.isEmpty {
            return args.joined(separator: " ")
        }

        return nil
    }

    private func cleanTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isTaskToolCall(_ update: ToolCallUpdate) -> Bool {
        isTaskToolCall(update._meta)
    }

    func isTaskToolCall(_ details: ToolCallUpdateDetails) -> Bool {
        isTaskToolCall(details._meta)
    }

    func isTaskToolCall(_ meta: [String: AnyCodable]?) -> Bool {
        guard let meta,
              let claudeCode = meta["claudeCode"]?.value as? [String: Any],
              let toolName = claudeCode["toolName"] as? String else {
            return false
        }
        return toolName == "Task"
    }

    func bufferToolCallUpdate(_ details: ToolCallUpdateDetails) {
        pendingToolCallUpdatesById[details.toolCallId, default: []].append(details)
    }

    func applyBufferedToolCallUpdatesIfPresent(for toolCallId: String) {
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

    func ensureToolCallExists(from details: ToolCallUpdateDetails, isTaskTool: Bool) -> Bool {
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

    func applyToolCallUpdate(_ details: ToolCallUpdateDetails, to updated: inout ToolCall) {
        var terminalOutputContent: [ToolCallContent] = []
        if let meta = details._meta {
            if let terminalOutput = meta["terminal_output"]?.value as? [String: Any],
               let outputData = terminalOutput["data"] as? String {
                let terminalContent = ToolCallContent.content(.text(TextContent(text: outputData)))
                terminalOutputContent.append(terminalContent)
            }

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

        var incomingContent = terminalOutputContent
        if let newContent = details.content, !newContent.isEmpty {
            incomingContent.append(contentsOf: newContent)
        }

        if !incomingContent.isEmpty {
            var allContent = updated.content
            allContent.append(contentsOf: incomingContent)
            updated.content = coalesceAdjacentTextBlocks(allContent)
        }
    }
}
