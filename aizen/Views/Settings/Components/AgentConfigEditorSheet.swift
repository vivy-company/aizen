//
//  AgentConfigEditorSheet.swift
//  aizen
//
//  Sheet for editing agent config files (config.toml, settings.json, etc.)
//

import SwiftUI

struct AgentConfigEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let configFile: AgentConfigFile
    let agentName: String

    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var validationError: String?

    private var hasChanges: Bool {
        content != originalContent
    }

    private var languageId: String {
        switch configFile.type {
        case .toml: return "toml"
        case .json: return "json"
        case .markdown: return "markdown"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeaderBar(showsBackground: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agentName) - \(configFile.name)")
                        .font(.headline)
                    Text(configFile.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } trailing: {
                if hasChanges {
                    TagBadge(
                        text: "Unsaved changes",
                        color: .orange,
                        font: .caption,
                        backgroundOpacity: 0.2,
                        textColor: .orange
                    )
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Editor
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CodeEditorView(
                    content: content,
                    language: languageId,
                    isEditable: true,
                    onContentChange: { newContent in
                        content = newContent
                        validateContent()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Validation error bar
            if let error = validationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.1))
            }

            Divider()

            // Footer
            HStack {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveFile()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving || validationError != nil)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 700, height: 500)
        .task {
            loadFile()
        }
    }

    private func loadFile() {
        let path = configFile.expandedPath
        if FileManager.default.fileExists(atPath: path) {
            do {
                content = try String(contentsOfFile: path, encoding: .utf8)
                originalContent = content
            } catch {
                errorMessage = "Failed to load file: \(error.localizedDescription)"
            }
        } else {
            // Create default content based on file type
            content = defaultContent()
            originalContent = ""
        }
        isLoading = false
    }

    private func defaultContent() -> String {
        switch configFile.type {
        case .toml:
            return "# \(agentName) Configuration\n\n"
        case .json:
            return "{\n  \n}\n"
        case .markdown:
            return "# \(agentName) Rules\n\n"
        }
    }

    private func validateContent() {
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
            // Basic TOML validation - check for obvious syntax errors
            if let error = validateTOML(content) {
                validationError = error
            }
        case .markdown:
            // No validation needed for markdown
            break
        }
    }

    private func validateTOML(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var inMultilineString = false
        var bracketStack: [Character] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Track multiline strings
            let tripleQuotes = trimmed.components(separatedBy: "\"\"\"").count - 1
            if tripleQuotes % 2 == 1 {
                inMultilineString.toggle()
            }

            if inMultilineString {
                continue
            }

            // Check bracket balance for arrays/tables
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

            // Check for basic key = value syntax (excluding table headers)
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

    private func saveFile() {
        isSaving = true
        errorMessage = nil

        let path = configFile.expandedPath
        let directory = (path as NSString).deletingLastPathComponent

        do {
            // Create directory if needed
            if !FileManager.default.fileExists(atPath: directory) {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            }

            // Write file
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            originalContent = content
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
