import ACP
import AppKit
import SwiftUI
import VVChatTimeline
import VVMetalPrimitives

extension ChatMessageList {
    func toolCallMarkdown(_ toolCall: ToolCall) -> String {
        toolCallSummaryBody(toolCall)
    }

    func toolCallHeaderTitle(_ toolCall: ToolCall) -> String {
        let base: String
        switch toolCall.kind {
        case .read:
            base = "Read"
        case .edit:
            base = "Edited"
        case .delete:
            base = "Deleted"
        case .move:
            base = "Moved"
        case .search:
            base = toolCallSearchHeaderTitle(toolCall) ?? "Searched"
        case .execute:
            if toolCallRawCommand(toolCall) != nil {
                base = "Ran"
            } else {
                base = toolCallInputPreview(toolCall) ?? sanitizedToolTitle(toolCall.title) ?? "Ran"
            }
        case .think:
            base = "Thought"
        case .fetch:
            base = "Fetched"
        case .switchMode:
            base = "Switched"
        case .plan:
            base = "Planned"
        case .exitPlanMode:
            base = "Exited plan"
        case .other:
            base = humanizedToolTitleAction(toolCall.title) ?? sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        case nil:
            base = humanizedToolTitleAction(toolCall.title) ?? sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        }

        switch toolCall.status.rawValue {
        case "in_progress":
            return "\(base)…"
        default:
            return base
        }
    }

    func toolCallHeaderBadges(_ toolCall: ToolCall) -> [VVHeaderBadge]? {
        var badges: [VVHeaderBadge] = []

        if let path = toolCallHeaderPath(toolCall) {
            badges.append(VVHeaderBadge(text: path, color: toolCallPathBadgeColor))
        }

        if toolCall.kind == .execute,
           let command = toolCallCommandBadgeText(toolCall) {
            badges.append(VVHeaderBadge(text: command, color: toolCallPathBadgeColor))
        }

        if let delta = toolCallAggregateDelta(toolCall) {
            let green: SIMD4<Float> = colorScheme == .dark
                ? .rgba(0.42, 0.82, 0.52, 1)
                : .rgba(0.14, 0.64, 0.24, 1)
            let red: SIMD4<Float> = colorScheme == .dark
                ? .rgba(0.92, 0.42, 0.44, 1)
                : .rgba(0.82, 0.24, 0.28, 1)
            badges.append(VVHeaderBadge(text: "+\(delta.added)", color: green))
            badges.append(VVHeaderBadge(text: "-\(delta.removed)", color: red))
            if delta.fileCount > 1 {
                let dimmed: SIMD4<Float> = colorScheme == .dark
                    ? .rgba(0.7, 0.7, 0.7, 0.6)
                    : .rgba(0.3, 0.3, 0.3, 0.6)
                badges.append(VVHeaderBadge(text: "\(delta.fileCount) files", color: dimmed))
            }
        } else if toolCall.kind != .edit,
                  let outcome = toolCallCompactOutcome(toolCall),
                  !toolCallHeaderTitle(toolCall).localizedCaseInsensitiveContains(outcome) {
            badges.append(VVHeaderBadge(text: outcome, color: toolCallPathBadgeColor))
        }

        return badges.isEmpty ? nil : badges
    }

    func toolCallHeaderPath(_ toolCall: ToolCall) -> String? {
        guard let path = primaryPath(for: toolCall) else { return nil }
        return compactDisplayPath(path)
    }

    var toolCallPathBadgeColor: SIMD4<Float> {
        colorScheme == .dark ? .rgba(0.72, 0.74, 0.79, 0.72) : .rgba(0.38, 0.42, 0.50, 0.78)
    }

    func toolCallDetailMarkdown(_ toolCall: ToolCall) -> String {
        toolCallSummaryBody(toolCall)
    }

}
