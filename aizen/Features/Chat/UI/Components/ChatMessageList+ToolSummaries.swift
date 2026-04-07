//
//  ChatMessageList+ToolSummaries.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation

extension ChatMessageList {
    func toolCallSummaryBody(_ toolCall: ToolCall) -> String {
        switch toolCall.kind {
        case .fetch:
            return fetchToolSummary(toolCall)
        case .think:
            if let text = firstTextContent(for: toolCall) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return abbreviated(trimmed, maxLength: 240)
                }
            }
            return ""
        case .execute:
            if let text = firstTextContent(for: toolCall) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return truncatedOutputBlock(trimmed, maxLines: 6)
                }
            }
            return ""
        case .read:
            return ""
        case .search:
            if let text = firstTextContent(for: toolCall) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return truncatedOutputBlock(trimmed, maxLines: 6)
                }
            }
            return ""
        case .edit, .delete, .move:
            return ""
        case .switchMode, .plan, .exitPlanMode:
            return ""
        case .other, nil:
            return genericToolSummary(toolCall)
        }
    }

    func fetchToolSummary(_ toolCall: ToolCall) -> String {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else {
            return firstTextContentPreview(toolCall, maxLines: 4)
        }
        if let url = nestedInputString(in: raw, preferredKeys: ["url", "uri", "href", "endpoint"]) {
            let display = abbreviated(url, maxLength: 120)
            let output = firstTextContentPreview(toolCall, maxLines: 4)
            if output.isEmpty {
                return display
            }
            return display + "\n\n" + output
        }
        return firstTextContentPreview(toolCall, maxLines: 4)
    }

    func genericToolSummary(_ toolCall: ToolCall) -> String {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else {
            return firstTextContentPreview(toolCall, maxLines: 4)
        }

        if let query = nestedInputString(in: raw, preferredKeys: ["query", "pattern", "search", "prompt", "question"]) {
            let display = abbreviated(query, maxLength: 160)
            let output = firstTextContentPreview(toolCall, maxLines: 4)
            if output.isEmpty {
                return display
            }
            return display + "\n\n" + output
        }

        if let url = nestedInputString(in: raw, preferredKeys: ["url", "uri", "href"]) {
            let display = abbreviated(url, maxLength: 120)
            let output = firstTextContentPreview(toolCall, maxLines: 4)
            if output.isEmpty {
                return display
            }
            return display + "\n\n" + output
        }

        if let path = nestedInputString(in: raw, preferredKeys: ["path", "file", "filePath"]) {
            return compactDisplayPath(path)
        }

        if let command = nestedInputString(in: raw, preferredKeys: ["command", "cmd"]) {
            return "`" + abbreviated(command, maxLength: 100) + "`"
        }

        return firstTextContentPreview(toolCall, maxLines: 4)
    }

    func firstTextContentPreview(_ toolCall: ToolCall, maxLines: Int) -> String {
        guard let text = firstTextContent(for: toolCall) else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return truncatedOutputBlock(trimmed, maxLines: maxLines)
    }

    func truncatedOutputBlock(_ text: String, maxLines: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= maxLines {
            return abbreviated(text, maxLength: maxLines * 120)
        }
        let preview = lines.prefix(maxLines).joined(separator: "\n")
        let remaining = lines.count - maxLines
        return abbreviated(preview, maxLength: maxLines * 120) + "\n… \(remaining) more line\(remaining == 1 ? "" : "s")"
    }
}
