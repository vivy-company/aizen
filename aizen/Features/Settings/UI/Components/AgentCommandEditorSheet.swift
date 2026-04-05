//
//  AgentCommandEditorSheet.swift
//  aizen
//
//  Sheet for editing or creating agent slash commands
//

import SwiftUI

struct AgentCommandEditorSheet: View {
    @Environment(\.dismiss) var dismiss

    let command: AgentCommand?
    let commandsDirectory: String
    let agentName: String
    let onDismiss: () -> Void

    @State var commandName: String = ""
    @State var content: String = ""
    @State var originalContent: String = ""
    @State var isSaving = false
    @State var isLoading = true
    @State var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    var isNewCommand: Bool {
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
                    TagBadge(
                        text: "Unsaved changes",
                        color: .orange,
                        font: .caption,
                        backgroundOpacity: 0.2,
                        textColor: .orange
                    )
                }
            }
            .background(AppSurfaceTheme.backgroundColor())

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
            .background(AppSurfaceTheme.backgroundColor())
        }
        .frame(width: 700, height: 500)
        .settingsSheetChrome()
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

}
