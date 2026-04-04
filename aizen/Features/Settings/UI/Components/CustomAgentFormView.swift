//
//  CustomAgentFormView.swift
//  aizen
//
//  Form for adding/editing custom agents
//

import SwiftUI

struct CustomAgentFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State var name: String
    @State private var description: String
    @State var executablePath: String
    @State var launchArgsText: String
    @State var environmentVariables: [AgentEnvironmentVariable]
    @State private var selectedSFSymbol: String
    @State private var showingSFSymbolPicker = false
    @State private var errorMessage: String?
    @State var isValidatingPath = false
    @State var pathValidationResult: PathValidation?

    let existingMetadata: AgentMetadata?
    let onSave: (AgentMetadata) -> Void
    let onCancel: () -> Void

    enum PathValidation {
        case valid
        case invalid(String)
    }

    init(
        existingMetadata: AgentMetadata? = nil,
        onSave: @escaping (AgentMetadata) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingMetadata = existingMetadata
        self.onSave = onSave
        self.onCancel = onCancel

        if let metadata = existingMetadata {
            _name = State(initialValue: metadata.name)
            _description = State(initialValue: metadata.description ?? "")
            _executablePath = State(initialValue: metadata.executablePath ?? "")
            _launchArgsText = State(initialValue: metadata.launchArgs.joined(separator: " "))
            _environmentVariables = State(initialValue: metadata.environmentVariables)

            switch metadata.iconType {
            case .sfSymbol(let symbol):
                _selectedSFSymbol = State(initialValue: symbol)
            case .customImage:
                _selectedSFSymbol = State(initialValue: "brain.head.profile")
            case .builtin:
                _selectedSFSymbol = State(initialValue: "brain.head.profile")
            }
        } else {
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _executablePath = State(initialValue: "")
            _launchArgsText = State(initialValue: "")
            _environmentVariables = State(initialValue: [])
            _selectedSFSymbol = State(initialValue: "brain.head.profile")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeaderBar(showsBackground: false) {
                Text(existingMetadata == nil ? "Add Custom Agent" : "Edit Agent")
                    .font(.headline)
            } trailing: {
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
            }
            .background(AppSurfaceTheme.backgroundColor())

            Divider()

            // Form
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                        .help("Display name for the agent")

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .help("Brief description of the agent")
                }

                executableSection

                AgentEnvironmentVariablesEditor(
                    variables: environmentVariablesBinding,
                    helperText: "Merged on top of your shell environment during validation and when the agent launches."
                )

                Section("Icon") {
                    HStack(spacing: 12) {
                        Image(systemName: selectedSFSymbol)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)

                        Text(selectedSFSymbol)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Choose Symbol...") {
                            showingSFSymbolPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(existingMetadata == nil ? "Add" : "Save") {
                    saveAgent()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
            .background(AppSurfaceTheme.backgroundColor())
        }
        .frame(width: 520, height: 720)
        .settingsSheetChrome()
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showingSFSymbolPicker) {
            SFSymbolPickerView(selectedSymbol: $selectedSFSymbol, isPresented: $showingSFSymbolPicker)
        }
    }

    private func saveAgent() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespaces)

        let launchArgs = parsedLaunchArgs

        // Use SF Symbol for icon
        let iconType = AgentIconType.sfSymbol(selectedSFSymbol)
        let persistedEnvironmentVariables = environmentVariables.persistedVariables

        Task {
            if let existing = existingMetadata {
                // Update existing
                var updated = existing
                updated.name = trimmedName
                updated.description = trimmedDescription.isEmpty ? nil : trimmedDescription
                updated.executablePath = trimmedPath
                updated.launchArgs = launchArgs
                updated.iconType = iconType
                updated.environmentVariables = persistedEnvironmentVariables

                await AgentRegistry.shared.updateAgent(updated)
                await MainActor.run {
                    onSave(updated)
                    dismiss()
                }
            } else {
                // Create new
                let metadata = await AgentRegistry.shared.addCustomAgent(
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    iconType: iconType,
                    executablePath: trimmedPath,
                    launchArgs: launchArgs,
                    environmentVariables: persistedEnvironmentVariables
                )
                await MainActor.run {
                    onSave(metadata)
                    dismiss()
                }
            }
        }
    }
}
