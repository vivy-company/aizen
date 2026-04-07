//
//  ChatMessageList+ToolInputParsing.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation

extension ChatMessageList {
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
}
