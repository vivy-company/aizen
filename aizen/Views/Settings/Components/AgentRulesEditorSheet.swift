//
//  AgentRulesEditorSheet.swift
//  aizen
//
//  Sheet for editing agent rules files (CLAUDE.md, AGENTS.md, etc.)
//

import SwiftUI

struct AgentRulesEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let configFile: AgentConfigFile
    let agentName: String
    let onDismiss: () -> Void

    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var hasChanges: Bool {
        content != originalContent
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
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundColor(.orange)
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
                    language: "markdown",
                    isEditable: true,
                    onContentChange: { newContent in
                        content = newContent
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveFile()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving)
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
            // Create empty file with header comment
            content = "# \(agentName) Global Rules\n\n"
            originalContent = ""
        }
        isLoading = false
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
            onDismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
