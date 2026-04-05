import Foundation
import SwiftUI

extension AgentConfigEditorSheet {
    func loadFile() {
        let path = configFile.expandedPath
        if FileManager.default.fileExists(atPath: path) {
            do {
                content = try String(contentsOfFile: path, encoding: .utf8)
                originalContent = content
            } catch {
                errorMessage = "Failed to load file: \(error.localizedDescription)"
            }
        } else {
            content = defaultContent()
            originalContent = ""
        }
        isLoading = false
    }

    func defaultContent() -> String {
        switch configFile.type {
        case .toml:
            return "# \(agentName) Configuration\n\n"
        case .json:
            return "{\n  \n}\n"
        case .markdown:
            return "# \(agentName) Rules\n\n"
        }
    }

    func validateContent() {
        validationError = nil

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        switch configFile.type {
        case .json:
            do {
                _ = try JSONSerialization.jsonObject(
                    with: Data(content.utf8),
                    options: []
                )
            } catch let error as NSError {
                validationError = "Invalid JSON: \(error.localizedDescription)"
            }
        case .toml:
            if let error = validateTOML(content) {
                validationError = error
            }
        case .markdown:
            break
        }
    }

    func validateTOML(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var inMultilineString = false
        var bracketStack: [Character] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let tripleQuotes = trimmed.components(separatedBy: "\"\"\"").count - 1
            if tripleQuotes % 2 == 1 {
                inMultilineString.toggle()
            }

            if inMultilineString {
                continue
            }

            for char in trimmed {
                if char == "[" || char == "{" {
                    bracketStack.append(char)
                } else if char == "]" {
                    if bracketStack.isEmpty || bracketStack.last != "[" {
                        return "Line \(index + 1): Unmatched ]"
                    }
                    bracketStack.removeLast()
                } else if char == "}" {
                    if bracketStack.isEmpty || bracketStack.last != "{" {
                        return "Line \(index + 1): Unmatched }"
                    }
                    bracketStack.removeLast()
                }
            }

            if !trimmed.hasPrefix("[") && trimmed.contains("=") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count < 2 {
                    return "Line \(index + 1): Invalid key-value pair"
                }
            }
        }

        if !bracketStack.isEmpty {
            return "Unclosed brackets: \(bracketStack)"
        }

        return nil
    }

    func saveFile() {
        isSaving = true
        errorMessage = nil

        let path = configFile.expandedPath
        let directory = (path as NSString).deletingLastPathComponent

        do {
            if !FileManager.default.fileExists(atPath: directory) {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            }

            try content.write(toFile: path, atomically: true, encoding: .utf8)
            originalContent = content
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
