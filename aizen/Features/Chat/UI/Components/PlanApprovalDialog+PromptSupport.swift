import ACP
import Foundation

extension RequestPermissionRequest {
    var promptDescription: PermissionRequestPrompt {
        if let rawInput = toolCall.rawInput?.value as? [String: Any],
           let plan = PermissionRequestPromptExtractor.stringValue(rawInput["plan"]),
           !plan.isEmpty {
            let title = normalizedMessage ?? "Implement this plan?"
            return PermissionRequestPrompt(title: title, detail: plan)
        }

        if let command = promptCommand, !command.isEmpty {
            return PermissionRequestPrompt(
                title: "Allow this command to run?",
                detail: command
            )
        }

        if let filePath = promptFilePath, !filePath.isEmpty {
            return PermissionRequestPrompt(
                title: "Allow this file to be modified?",
                detail: filePath
            )
        }

        if let url = promptURL, !url.isEmpty {
            return PermissionRequestPrompt(
                title: "Allow this URL to be opened?",
                detail: url
            )
        }

        return PermissionRequestPrompt(
            title: normalizedMessage ?? "Choose an option",
            detail: nil
        )
    }

    private var normalizedMessage: String? {
        guard let normalized = toolCall.title?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private var promptCommand: String? {
        guard let rawInput = toolCall.rawInput?.value as? [String: Any] else {
            return nil
        }
        return PermissionRequestPromptExtractor.commandValue(
            in: rawInput,
            preferredKeys: ["command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"]
        )
    }

    private var promptFilePath: String? {
        guard let rawInput = toolCall.rawInput?.value as? [String: Any] else {
            return nil
        }
        return PermissionRequestPromptExtractor.stringValue(
            in: rawInput,
            preferredKeys: ["file_path", "path", "filePath", "filepath", "file"]
        )
    }

    private var promptURL: String? {
        guard let rawInput = toolCall.rawInput?.value as? [String: Any] else {
            return nil
        }
        return PermissionRequestPromptExtractor.stringValue(
            in: rawInput,
            preferredKeys: ["url", "uri", "href"]
        )
    }
}

enum PermissionRequestPromptExtractor {
    static func stringValue(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = stringValue(dict[key]) {
                return value
            }
        }
        return nil
    }

    static func commandValue(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = commandValue(dict[key]) {
                return value
            }
        }
        return nil
    }

    static func stringValue(_ value: Any?, depth: Int = 0) -> String? {
        guard depth < 8, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dict = value as? [String: Any] {
            for key in ["value", "text", "path", "file_path", "filePath", "filepath", "url", "uri", "href", "command"] {
                if let nested = stringValue(dict[key], depth: depth + 1) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let nested = stringValue(item, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }

    static func commandValue(_ value: Any?, depth: Int = 0) -> String? {
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
            for key in ["value", "text", "command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"] {
                if let nested = commandValue(dict[key], depth: depth + 1) {
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
                if let nested = commandValue(item, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }
}
