//
//  AgentConfigEditorSheet.swift
//  aizen
//
//  Sheet for editing agent config files (config.toml, settings.json, etc.)
//

import SwiftUI

struct AgentConfigEditorSheet: View {
    @Environment(\.dismiss) var dismiss

    let configFile: AgentConfigFile
    let agentName: String

    @State var content: String = ""
    @State var originalContent: String = ""
    @State var isSaving = false
    @State var isLoading = true
    @State var errorMessage: String?
    @State var validationError: String?

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
            .background(AppSurfaceTheme.backgroundColor())

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
            .background(AppSurfaceTheme.backgroundColor())
        }
        .frame(width: 700, height: 500)
        .settingsSheetChrome()
        .task {
            loadFile()
        }
    }

}
