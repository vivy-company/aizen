//
//  CustomAgentFormView.swift
//  aizen
//
//  Form for adding/editing custom agents
//

import SwiftUI
import UniformTypeIdentifiers

struct CustomAgentFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var executablePath: String
    @State private var launchArgsText: String
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
            .background(Color(NSColor.controlBackgroundColor))

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
                        TextField("Path", text: $executablePath)
                            .textFieldStyle(.roundedBorder)
                            .help("Enter or paste executable path, or use Browse button")
                            .onChange(of: executablePath) { _ in
                                pathValidationResult = nil
                            }
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

                    TextField("Launch arguments (optional)", text: $launchArgsText)
                        .textFieldStyle(.roundedBorder)
                        .help("Space-separated arguments (e.g., agent stdio, --experimental-acp)")
                        .onChange(of: launchArgsText) { _ in
                            pathValidationResult = nil
                        }
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
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 600)
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
                    executablePath = url.path
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
                executablePath = url.path
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

        // Parse launch args
        let launchArgs = launchArgsText
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        // Test ACP protocol
        do {
            let tempClient = ACPClient()

            try await tempClient.launch(
                agentPath: trimmedPath,
                arguments: launchArgs
            )

            let capabilities = ClientCapabilities(
                fs: FileSystemCapabilities(
                    readTextFile: true,
                    writeTextFile: true
                ),
                terminal: true,
                meta: [
                    "terminal_output": AnyCodable(true),
                    "terminal-auth": AnyCodable(true)
                ]
            )

            let initResponse = try await tempClient.initialize(
                protocolVersion: 1,
                capabilities: capabilities
            )

            // If agent requires authentication, that's still valid - we just can't test session creation
            if let authMethods = initResponse.authMethods, !authMethods.isEmpty {
                pathValidationResult = .valid
                await tempClient.terminate()
            } else {
                // Try to create a session to fully validate
                _ = try await tempClient.newSession(
                    workingDirectory: FileManager.default.currentDirectoryPath,
                    mcpServers: []
                )
                pathValidationResult = .valid
                await tempClient.terminate()
            }
        } catch {
            pathValidationResult = .invalid("Not a valid ACP executable: \(error.localizedDescription)")
        }

        await MainActor.run {
            isValidatingPath = false
        }
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

    private func saveAgent() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespaces)

        // Parse launch args
        let launchArgs = launchArgsText
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        // Use SF Symbol for icon
        let iconType = AgentIconType.sfSymbol(selectedSFSymbol)

        Task {
            if let existing = existingMetadata {
                // Update existing
                var updated = existing
                updated.name = trimmedName
                updated.description = trimmedDescription.isEmpty ? nil : trimmedDescription
                updated.executablePath = trimmedPath
                updated.launchArgs = launchArgs
                updated.iconType = iconType

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
                    launchArgs: launchArgs
                )
                await MainActor.run {
                    onSave(metadata)
                    dismiss()
                }
            }
        }
    }
}
