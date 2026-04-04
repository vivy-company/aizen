//
//  CustomAgentFormView.swift
//  aizen
//
//  Form for adding/editing custom agents
//

import ACP
import SwiftUI
import UniformTypeIdentifiers

struct CustomAgentFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var executablePath: String
    @State private var launchArgsText: String
    @State private var environmentVariables: [AgentEnvironmentVariable]
    @State private var selectedSFSymbol: String
    @State private var showingSFSymbolPicker = false
    @State private var errorMessage: String?
    @State private var isValidatingPath = false
    @State private var pathValidationResult: PathValidation?

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

                Section("ACP Executable") {
                    HStack(spacing: 8) {
                        TextField("Path", text: executablePathBinding)
                            .textFieldStyle(.roundedBorder)
                            .help("Enter or paste executable path, or use Browse button")
                            .onSubmit {
                                Task {
                                    await validateExecutablePath()
                                }
                            }

                        Button("Browse...") {
                            selectExecutableFile()
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("Launch arguments (optional)", text: launchArgsTextBinding)
                        .textFieldStyle(.roundedBorder)
                        .help("Space-separated arguments (e.g., agent stdio, --experimental-acp)")
                        .onSubmit {
                            Task {
                                await validateExecutablePath()
                            }
                        }

                    // Validation status row (automatically validates on blur/submit)
                    if !executablePath.isEmpty {
                        HStack(spacing: 8) {
                            if isValidatingPath {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .controlSize(.small)
                                Text("Validating ACP executable...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let validation = pathValidationResult {
                                switch validation {
                                case .valid:
                                    ValidationStatusIcon(isValid: true)
                                    Text("Valid ACP executable")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                case .invalid(let message):
                                    ValidationStatusIcon(isValid: false)
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            } else {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text("Press Enter to validate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

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

    private func selectExecutableFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select ACP executable"
        panel.prompt = "Select"

        // Use beginSheetModal to attach to the current window
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    updateExecutablePath(url.path)
                    // Auto-validate after selection
                    Task {
                        await validateExecutablePath()
                    }
                }
            }
        } else {
            // Fallback to modal panel
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                updateExecutablePath(url.path)
                // Auto-validate after selection
                Task {
                    await validateExecutablePath()
                }
            }
        }
    }


    private func validateExecutablePath() async {
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespaces)

        guard !trimmedPath.isEmpty else {
            pathValidationResult = .invalid("Path is empty")
            return
        }

        // Check file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: trimmedPath) else {
            pathValidationResult = .invalid("File does not exist")
            return
        }

        guard fileManager.isExecutableFile(atPath: trimmedPath) else {
            pathValidationResult = .invalid("File is not executable")
            return
        }

        isValidatingPath = true

        let launchArgs = parsedLaunchArgs
        let environment = environmentVariables.launchEnvironment
        let validationMessage = await CustomAgentExecutableValidator.validate(
            executablePath: trimmedPath,
            launchArgs: launchArgs,
            environment: environment
        )
        pathValidationResult = validationMessage.map(PathValidation.invalid) ?? .valid

        await MainActor.run {
            isValidatingPath = false
        }
    }

    private var executablePathBinding: Binding<String> {
        Binding(
            get: { executablePath },
            set: { updateExecutablePath($0) }
        )
    }

    private var launchArgsTextBinding: Binding<String> {
        Binding(
            get: { launchArgsText },
            set: { updateLaunchArgsText($0) }
        )
    }

    private var environmentVariablesBinding: Binding<[AgentEnvironmentVariable]> {
        Binding(
            get: { environmentVariables },
            set: { updateEnvironmentVariables($0) }
        )
    }

    private func updateExecutablePath(_ newValue: String) {
        executablePath = newValue
        pathValidationResult = nil
    }

    private func updateLaunchArgsText(_ newValue: String) {
        launchArgsText = newValue
        pathValidationResult = nil
    }

    private func updateEnvironmentVariables(_ newValue: [AgentEnvironmentVariable]) {
        environmentVariables = newValue
        pathValidationResult = nil
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty && !trimmedPath.isEmpty else {
            return false
        }

        // Require successful validation
        if case .valid = pathValidationResult {
            return true
        }

        return false
    }

    private var parsedLaunchArgs: [String] {
        launchArgsText
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }
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
