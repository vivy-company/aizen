//
//  AgentCommandEditorSheet.swift
//  aizen
//
//  Sheet for editing or creating agent slash commands
//

import SwiftUI

struct AgentCommandEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let command: AgentCommand?
    let commandsDirectory: String
    let agentName: String
    let onDismiss: () -> Void

    @State private var commandName: String = ""
    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    private var isNewCommand: Bool {
        command == nil
    }

    private var hasChanges: Bool {
        if isNewCommand {
            return !commandName.isEmpty || !content.isEmpty
        }
        return content != originalContent
    }

    private var isValid: Bool {
        if isNewCommand {
            return !commandName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeaderBar(showsBackground: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if isNewCommand {
                        Text("New Command")
                            .font(.headline)
                    } else {
                        Text("/\(command?.name ?? "")")
                            .font(.headline)
                    }
                    Text(agentName)
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

            // Command name field (for new commands)
            if isNewCommand {
                HStack {
                    Text("/")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("command-name", text: $commandName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                .padding()

                Divider()
            }

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

                if !isNewCommand {
                    Button("Delete", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveCommand()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || !isValid || isSaving)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 700, height: 500)
        .task {
            loadCommand()
        }
        .alert("Delete Command", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCommand()
            }
        } message: {
            Text("Are you sure you want to delete this command? This cannot be undone.")
        }
    }

    private func loadCommand() {
        if let command = command {
            commandName = command.name
            if let fileContent = command.content {
                content = fileContent
                originalContent = fileContent
            }
        } else {
            content = ""
            originalContent = ""
        }
        isLoading = false
    }

    private func saveCommand() {
        isSaving = true
        errorMessage = nil

        let name = isNewCommand ? commandName.trimmingCharacters(in: .whitespaces) : (command?.name ?? "")
        let filename = "\(name).md"
        let path = (commandsDirectory as NSString).appendingPathComponent(filename)

        do {
            // Create directory if needed
            if !FileManager.default.fileExists(atPath: commandsDirectory) {
                try FileManager.default.createDirectory(
                    atPath: commandsDirectory,
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

    private func deleteCommand() {
        guard let command = command else { return }

        do {
            try FileManager.default.removeItem(atPath: command.path)
            dismiss()
            onDismiss()
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }
}
