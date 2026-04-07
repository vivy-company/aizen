//
//  ChatMessageList+ToolGrouping.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation

extension ChatMessageList {
    func toolCallGroupTitle(_ group: ToolCallGroup) -> String {
        var segments: [String] = [
            toolGroupActionSummary(group)
        ]
        if let duration = group.formattedDuration {
            segments.append(duration)
        }
        return segments.joined(separator: " • ")
    }

    func toolGroupActionSummary(_ group: ToolCallGroup) -> String {
        var kindCounts: [(label: String, count: Int)] = []
        var counts: [String: Int] = [:]
        var orderedLabels: [String] = []

        for call in group.toolCalls {
            let label = toolKindShortLabel(call.kind)
            counts[label, default: 0] += 1
            if !orderedLabels.contains(label) {
                orderedLabels.append(label)
            }
        }

        for label in orderedLabels {
            kindCounts.append((label: label, count: counts[label]!))
        }

        if kindCounts.count == 1 {
            let item = kindCounts[0]
            return "\(item.label) \(item.count) file\(item.count == 1 ? "" : "s")"
        }

        return kindCounts.map { "\($0.label) \($0.count)" }.joined(separator: ", ")
    }

    func toolKindShortLabel(_ kind: ToolKind?) -> String {
        switch kind {
        case .read: return "Read"
        case .edit: return "Edited"
        case .delete: return "Deleted"
        case .move: return "Moved"
        case .search: return "Searched"
        case .execute: return "Ran"
        case .think: return "Thought"
        case .fetch: return "Fetched"
        case .plan: return "Planned"
        case .switchMode: return "Switched"
        case .exitPlanMode: return "Exited plan"
        case .other, nil: return "Ran"
        }
    }

    func toolCallGroupMarkdown(_ group: ToolCallGroup, isExpanded: Bool) -> String {
        guard !isExpanded else { return "" }
        var lines: [String] = []
        for call in group.toolCalls.prefix(8) {
            let action = toolCallHumanAction(call)
            lines.append("- \(action)")
        }
        if group.toolCalls.count > 8 {
            lines.append("- … \(group.toolCalls.count - 8) more")
        }
        return lines.joined(separator: "\n")
    }

    func toolCallHumanAction(_ toolCall: ToolCall) -> String {
        switch toolCall.kind {
        case .read:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Read \(target)"
            }
            return "Read a file"
        case .edit:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Edited \(target)"
            }
            return "Edited a file"
        case .delete:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Deleted \(target)"
            }
            return "Deleted a file"
        case .move:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Moved \(target)"
            }
            return "Moved a file"
        case .search:
            if let target = toolCallPrimaryTarget(toolCall) {
                if target.lowercased().hasPrefix("searched ") {
                    return target
                }
                return "Searched \(target)"
            }
            return "Searched files"
        case .execute:
            return toolCallInputPreview(toolCall) ?? "Ran a shell command"
        case .think:
            return "Reasoned about the next step"
        case .fetch:
            return "Fetched data"
        case .switchMode:
            return "Switched mode"
        case .plan:
            return "Updated plan"
        case .exitPlanMode:
            return "Exited plan mode"
        case .other:
            if let titleAction = humanizedToolTitleAction(toolCall.title) {
                return titleAction
            }
            return sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        case nil:
            if let titleAction = humanizedToolTitleAction(toolCall.title) {
                return titleAction
            }
            return sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        }
    }

    func toolCallPrimaryTarget(_ toolCall: ToolCall) -> String? {
        if let path = primaryPath(for: toolCall) {
            return compactDisplayPath(path)
        }
        if let input = toolCallInputPreview(toolCall) {
            return abbreviated(input, maxLength: 120)
        }
        return sanitizedToolTitle(toolCall.title)
    }

    func toolCallInputPreview(_ toolCall: ToolCall) -> String? {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else { return nil }

        if let command = toolCallRawCommand(toolCall) {
            return humanizedCommandPreview(command)
        }
        if let query = nestedInputString(in: raw, preferredKeys: ["query", "pattern", "glob"]) {
            return "Searched \(abbreviated(query, maxLength: 80))"
        }
        if let path = nestedInputString(in: raw, preferredKeys: ["path", "file", "filePath", "filepath"]) {
            return compactDisplayPath(path)
        }

        return nil
    }

    func toolCallSearchHeaderTitle(_ toolCall: ToolCall) -> String? {
        if let input = toolCallInputPreview(toolCall) {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.lowercased().hasPrefix("searched ") {
                return abbreviated(trimmed, maxLength: 96)
            }
            return "Searched \(abbreviated(trimmed, maxLength: 88))"
        }

        if let action = humanizedToolTitleAction(toolCall.title) {
            let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.lowercased().hasPrefix("searched ") {
                return abbreviated(trimmed, maxLength: 96)
            }
        }

        return nil
    }

    func toolGroupStatusRawValue(_ group: ToolCallGroup) -> String {
        if group.hasFailed { return "failed" }
        if group.isInProgress { return "in_progress" }
        return "completed"
    }
}
