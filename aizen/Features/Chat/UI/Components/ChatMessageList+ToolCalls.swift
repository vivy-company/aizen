import ACP
import AppKit
import SwiftUI
import VVChatTimeline
import VVMetalPrimitives

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

    func toolCallCommandBadgeText(_ toolCall: ToolCall) -> String? {
        guard let command = toolCallRawCommand(toolCall) else { return nil }
        return abbreviated(singleLineBadgeText(command), maxLength: 88)
    }

    func toolCallRawCommand(_ toolCall: ToolCall) -> String? {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else { return nil }
        return nestedCommandString(
            in: raw,
            preferredKeys: ["command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"]
        )
    }

    func singleLineBadgeText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    func nestedCommandString(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = recursiveCommandValue(dict[key], preferredKey: key) {
                return value
            }
        }
        return nil
    }

    func nestedInputString(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = recursiveStringValue(dict[key], preferredKey: key) {
                return value
            }
        }
        return nil
    }

    func recursiveStringValue(_ value: Any?, preferredKey: String, depth: Int = 0) -> String? {
        guard depth < 8, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dict = value as? [String: Any] {
            if let nested = recursiveStringValue(dict[preferredKey], preferredKey: preferredKey, depth: depth + 1) {
                return nested
            }
            for fallback in ["value", "text", "path", "query", "pattern", "command"] {
                if let nested = recursiveStringValue(dict[fallback], preferredKey: preferredKey, depth: depth + 1) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let nested = recursiveStringValue(item, preferredKey: preferredKey, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }

    func recursiveCommandValue(_ value: Any?, preferredKey: String, depth: Int = 0) -> String? {
        guard depth < 8, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let strings = value as? [String] {
            let cleaned = strings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned.joined(separator: " ")
        }

        if let dict = value as? [String: Any] {
            if let nested = recursiveCommandValue(dict[preferredKey], preferredKey: preferredKey, depth: depth + 1) {
                return nested
            }
            for fallback in ["value", "text", "command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"] {
                if let nested = recursiveCommandValue(dict[fallback], preferredKey: preferredKey, depth: depth + 1) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            let strings = array.compactMap { item -> String? in
                guard let string = item as? String else { return nil }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !strings.isEmpty {
                return strings.joined(separator: " ")
            }
            for item in array {
                if let nested = recursiveCommandValue(item, preferredKey: preferredKey, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }

    func humanizedCommandPreview(_ rawCommand: String) -> String {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "Ran a shell command" }

        let primary = command.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? command
        let tokens = primary.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = tokens.first?.lowercased() else {
            return "Ran a shell command"
        }

        switch executable {
        case "ls":
            let args = Array(tokens.dropFirst())
            if let target = lastNonOptionToken(in: args) {
                return "Listed \(compactDisplayPath(unquoted(target)))"
            }
            return "Listed files"
        case "find":
            if let target = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                return "Searched \(compactDisplayPath(unquoted(target)))"
            }
            return "Searched files"
        case "cat", "head", "tail":
            if let target = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                return "Read \(compactDisplayPath(unquoted(target)))"
            }
            return "Read command output"
        case "rg", "grep":
            return "Searched text"
        default:
            return abbreviated(command, maxLength: 120)
        }
    }

    func lastNonOptionToken(in tokens: [String]) -> String? {
        tokens.reversed().first { !$0.hasPrefix("-") }
    }

    func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    func humanizedToolTitleAction(_ rawTitle: String) -> String? {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let kind = trimmed[..<colon].lowercased()
        let rawTarget = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let target = unquoted(rawTarget)

        switch kind {
        case "readfile", "read":
            return target.isEmpty ? "Read a file" : "Read \(compactDisplayPath(target))"
        case "strreplacefile", "editfile", "writefile", "replacefile", "edit":
            return target.isEmpty ? "Edited a file" : "Edited \(compactDisplayPath(target))"
        case "glob", "search", "find":
            return target.isEmpty ? "Searched files" : "Searched \(abbreviated(target, maxLength: 80))"
        case "shell", "exec", "command":
            return target.isEmpty ? "Ran shell command" : humanizedCommandPreview(target)
        case "list", "ls":
            return target.isEmpty ? "Listed files" : "Listed \(compactDisplayPath(target))"
        default:
            return nil
        }
    }

    func sanitizedToolTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return nil
        }
        if trimmed.contains("\"command\"") || trimmed.contains("\"path\"") {
            return nil
        }
        return abbreviated(trimmed, maxLength: 120)
    }

    func abbreviated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<index]) + "…"
    }

    func toolGroupStatusRawValue(_ group: ToolCallGroup) -> String {
        if group.hasFailed { return "failed" }
        if group.isInProgress { return "in_progress" }
        return "completed"
    }
}
