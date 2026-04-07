//
//  ChatMessageList+ToolContent.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation
import VVChatTimeline

extension ChatMessageList {
    func toolCallCompactOutcome(_ toolCall: ToolCall) -> String? {
        if let text = firstTextContent(for: toolCall) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.localizedCaseInsensitiveContains("no matches") {
                    return "0 matches"
                }
                let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).count
                if toolCall.kind == .read {
                    return "\(lines) line\(lines == 1 ? "" : "s")"
                }
            }
        }

        if toolCall.status == .failed {
            return "failed"
        }
        return nil
    }

    func toolCallAggregateDeltaText(_ toolCall: ToolCall) -> String? {
        guard let delta = toolCallAggregateDelta(toolCall) else { return nil }
        let deltaText = "+\(delta.added) -\(delta.removed)"
        if delta.fileCount > 1 {
            return "\(deltaText) · \(delta.fileCount) files"
        }
        return deltaText
    }

    func toolCallAggregateDelta(_ toolCall: ToolCall) -> (added: Int, removed: Int, fileCount: Int)? {
        let diffs = toolDiffContents(for: toolCall)
        guard !diffs.isEmpty else { return nil }

        var added = 0
        var removed = 0
        for diff in diffs {
            let delta = toolCallDiffDelta(diff)
            added += delta.added
            removed += delta.removed
        }
        return (added, removed, diffs.count)
    }

    func toolCallDiffDelta(_ diff: ToolCallDiff) -> (added: Int, removed: Int) {
        diffLineDelta(oldText: diff.oldText, newText: diff.newText)
    }

    func inlineDiffEntries(for toolCall: ToolCall, entryIDPrefix: String) -> [VVChatTimelineEntry] {
        let diffs = toolDiffContents(for: toolCall)
        guard !diffs.isEmpty else { return [] }

        return diffs.enumerated().map { index, diff in
            let unifiedDiff = inlineDiffPreviewDocument(for: diff)
            let payload = TimelineCustomPayload(
                title: nil,
                body: unifiedDiff,
                status: toolCall.status.rawValue,
                toolKind: toolCall.kind?.rawValue,
                showsAgentLaneIcon: false
            )
            return .custom(
                VVCustomTimelineEntry(
                    id: "\(entryIDPrefix)::diff::\(index)",
                    kind: "toolCallInlineDiff",
                    payload: encodeCustomPayload(payload, fallback: unifiedDiff),
                    revision: revisionKey(unifiedDiff + diff.path + "\(index)" + toolCall.status.rawValue),
                    timestamp: toolCall.timestamp
                )
            )
        }
    }

    func firstTextContent(for toolCall: ToolCall) -> String? {
        for content in toolCall.content {
            guard case .content(let block) = content else { continue }
            if case .text(let text) = block {
                let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return text.text
                }
            }
        }
        return nil
    }

    func compactDisplayPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawPath }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let components = expanded.split(separator: "/", omittingEmptySubsequences: true)
        if components.count <= 4 {
            return expanded
        }
        return "…/" + components.suffix(4).joined(separator: "/")
    }

    func toolDiffContents(for toolCall: ToolCall) -> [ToolCallDiff] {
        toolCall.content.compactMap { content in
            if case .diff(let diff) = content {
                return diff
            }
            return nil
        }
    }
}
