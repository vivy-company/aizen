import ACP
import Foundation

extension ChatMessageList {
    func isExplorationCandidate(_ toolCall: ToolCall) -> Bool {
        if let kind = toolCall.kind {
            let rawValue = kind.rawValue.lowercased()
            if rawValue == "read" || rawValue == "search" || rawValue == "grep" || rawValue == "list" {
                return true
            }
            if kind == .execute && hasListIntent(toolCall) {
                return true
            }
        }

        return hasListIntent(toolCall)
    }

    func hasListIntent(_ toolCall: ToolCall) -> Bool {
        let normalizedTitle = toolCall.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedTitle.hasPrefix("list ") || normalizedTitle == "list" {
            return true
        }

        if let rawInput = toolCall.rawInput?.value as? [String: Any] {
            if let command = rawInput["command"] as? String, isListCommand(command) {
                return true
            }
            if let cmd = rawInput["cmd"] as? String, isListCommand(cmd) {
                return true
            }
            if let args = rawInput["args"] as? [String], isListCommand(args.joined(separator: " ")) {
                return true
            }
        }

        return false
    }

    func isListCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }

        let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if ["ls", "find", "fd", "tree", "dir", "rg", "ripgrep", "grep", "glob"].contains(firstToken) {
            return true
        }

        return trimmed.contains(" --files") || trimmed.hasPrefix("list ")
    }
}
