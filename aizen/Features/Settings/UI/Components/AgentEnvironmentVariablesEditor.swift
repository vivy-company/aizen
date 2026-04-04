//
//  AgentEnvironmentVariablesEditor.swift
//  aizen
//
//  Native settings-style editor for per-agent environment variable overrides.
//

import SwiftUI
import UniformTypeIdentifiers

struct AgentEnvironmentVariablesEditor: View {
    @Binding var variables: [AgentEnvironmentVariable]

    var helperText: String = "Merged on top of your shell environment each time Aizen launches the agent."

    @State var revealedSecretIDs: Set<UUID> = []
    @State private var showingFileImporter = false
    @State private var showingTextEditor = false
    @State var importError: String?

    var duplicateNames: [String] {
        variables.duplicateNames
    }

    private var ignoredValueCount: Int {
        variables.ignoredValueCount
    }

    var body: some View {
        Section {
            if variables.isEmpty {
                emptyState
            } else {
                variablesList
            }

            addButton

            diagnostics
        } header: {
            Text("Environment Variables")
        } footer: {
            Text(helperText)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    let actionButtonsWidth: CGFloat = 54 // lock (24) + spacing (6) + remove (24)

    // MARK: - Field Components

    /// Plain-style TextField with full-width hit area.
    /// Each instance owns its own @FocusState so an invisible overlay can
    /// forward clicks that land outside the tiny underlying NSTextField.
    struct PlainTextField: View {
        @Binding var text: String
        var isDuplicate: Bool = false
        @FocusState private var isFocused: Bool

        var body: some View {
            TextField(text: $text, prompt: nil) {}
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isFocused)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isDuplicate ? Color.orange.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .overlay {
                    if !isFocused {
                        Color.white.opacity(0.001)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .onTapGesture { isFocused = true }
                    }
                }
        }
    }

    struct PlainSecureField: View {
        @Binding var text: String
        @FocusState private var isFocused: Bool

        var body: some View {
            SecureField(text: $text, prompt: nil) {}
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isFocused)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .overlay {
                    if !isFocused {
                        Color.white.opacity(0.001)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .onTapGesture { isFocused = true }
                    }
                }
        }
    }

    // MARK: - Actions

    private var addButton: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    variables.append(AgentEnvironmentVariable())
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Add Variable")
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("From File", systemImage: "doc")
                }

                Button {
                    importFromClipboard()
                } label: {
                    Label("From Clipboard", systemImage: "doc.on.clipboard")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.accentColor)
                    Text("Import")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                importEnvFile(result: result)
            }

            Menu {
                ForEach(EnvironmentVariablePreset.categories, id: \.name) { category in
                    Section(category.name) {
                        ForEach(category.presets) { preset in
                            Button(preset.name) {
                                applyPreset(preset)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .foregroundStyle(Color.accentColor)
                    Text("Presets")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let error = importError {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button {
                showingTextEditor = true
            } label: {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Edit as text — bulk add/edit variables in KEY=VALUE format")
        }
        .sheet(isPresented: $showingTextEditor) {
            EnvironmentVariablesTextEditorSheet(variables: $variables)
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private var diagnostics: some View {
        if ignoredValueCount > 0 {
            Label {
                Text("Rows without a name are ignored at launch")
                    .font(.caption)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.secondary)
        }

        if !duplicateNames.isEmpty {
            Label {
                Text("Duplicate names (\(duplicateNames.joined(separator: ", "))): last value wins")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.secondary)
        }
    }

}
