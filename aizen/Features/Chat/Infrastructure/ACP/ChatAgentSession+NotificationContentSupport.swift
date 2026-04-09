//
//  ChatAgentSession+NotificationContentSupport.swift
//  aizen
//
//  Content decoding and tool-call mapping helpers for ACP notifications.
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    /// Merge adjacent text blocks to avoid fragment spam from streamed chunks.
    func coalesceAdjacentTextBlocks(_ blocks: [ContentBlock]) -> [ContentBlock] {
        var result: [ContentBlock] = []

        for block in blocks {
            if case .text(let newText) = block, let last = result.last, case .text(let lastText) = last {
                if lastText.text == newText.text {
                    continue
                }
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
            if case .diff(let diff) = block {
                if seenDiffPaths.contains(diff.path) {
                    continue
                }
                seenDiffPaths.insert(diff.path)
                result.append(block)
                continue
            }

            if case .content(let contentBlock) = block,
               case .text(let newText) = contentBlock,
               let last = result.last,
               case .content(let lastContentBlock) = last,
               case .text(let lastText) = lastContentBlock {
                if lastText.text == newText.text {
                    continue
                }
                result.removeLast()
                let combined = TextContent(text: lastText.text + newText.text)
                result.append(.content(.text(combined)))
            } else {
                result.append(block)
            }
        }

        return result
    }

    /// Extract plain text from a content block (best effort).
    func textAndContent(from block: ContentBlock) -> (String, [ContentBlock]) {
        switch block {
        case .text(let text):
            return (text.text, [.text(text)])
        default:
            return ("", [block])
        }
    }
}

extension ToolCallUpdate {
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
