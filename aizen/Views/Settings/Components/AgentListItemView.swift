//
//  AgentListItemView.swift
//  aizen
//
//  Agent list item component for Settings
//

import SwiftUI
import UniformTypeIdentifiers

struct AgentListItemView: View {
    @Binding var metadata: AgentMetadata
    @State private var isInstalling = false
    @State private var isUpdating = false
    @State private var isTesting = false
    @State private var canUpdate = false
    @State private var isAgentValid = false
    @State private var testResult: String?
    @State private var showingFilePicker = false
    @State private var showingEditSheet = false
    @State private var errorMessage: String?
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                AgentIconView(metadata: metadata, size: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(metadata.name)
                            .font(.headline)

                        if !metadata.isBuiltIn {
                            Text("Custom")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                    if let description = metadata.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Enable/Disable switch
                Toggle("", isOn: Binding(
                    get: { metadata.isEnabled },
                    set: { newValue in
                        let wasEnabled = metadata.isEnabled
                        metadata.isEnabled = newValue
                        Task {
                            await AgentRegistry.shared.updateAgent(metadata)

                            // If we're disabling the current default agent, pick a new default
                            if wasEnabled && !newValue {
                                let defaultAgent = UserDefaults.standard.string(forKey: "defaultACPAgent") ?? "claude"
                                if defaultAgent == metadata.id {
                                    // Find first enabled agent that's not this one
                                    if let newDefault = await AgentRegistry.shared.getEnabledAgents().first {
                                        await MainActor.run {
                                            UserDefaults.standard.set(newDefault.id, forKey: "defaultACPAgent")
                                        }
                                    }
                                }
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(metadata.isEnabled ? "Disable agent" : "Enable agent")

                // Edit button for custom agents
                if !metadata.isBuiltIn {
                    Button(action: { showingEditSheet = true }) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit agent")
                }
            }

            // Configuration (only show if enabled)
            if metadata.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    // Path field
                    HStack(spacing: 8) {
                        TextField("Executable path", text: Binding(
                            get: { metadata.executablePath ?? "" },
                            set: { newValue in
                                metadata.executablePath = newValue.isEmpty ? nil : newValue
                                Task {
                                    await AgentRegistry.shared.updateAgent(metadata)
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            showingFilePicker = true
                        }
                        .buttonStyle(.bordered)

                        // Validation indicator
                        if let path = metadata.executablePath, !path.isEmpty {
                            if isAgentValid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .help("Executable is valid")
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .help("Executable not found or not executable")
                            }
                        }
                    }

                    // Launch args
                    if !metadata.launchArgs.isEmpty {
                        Text("Launch args: \(metadata.launchArgs.joined(separator: " "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        // Install button (only for built-in with install method)
                        // Don't show install button while updating
                        if metadata.isBuiltIn,
                           metadata.installMethod != nil,
                           !isAgentValid,
                           !isUpdating {
                            if isInstalling {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("Installing...")
                                    .font(.caption)
                            } else {
                                Button("Install") {
                                    Task {
                                        await installAgent()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        // Update button (for agents installed in .aizen/agents)
                        // Show updating status even if validation fails during update
                        if canUpdate && (isAgentValid || isUpdating) {
                            if isUpdating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("Updating...")
                                    .font(.caption)
                            } else {
                                Button("Update") {
                                    Task {
                                        await updateAgent()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .help("Update to latest version")
                            }
                        }

                        // Test Connection button (only if valid)
                        if isAgentValid {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("Testing...")
                                    .font(.caption)
                            } else {
                                Button("Test Connection") {
                                    Task {
                                        await testConnection()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }

                            if let result = testResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(result.contains("Success") ? .green : .red)
                            }
                        }

                        Spacer()

                        // Delete button for custom agents
                        if !metadata.isBuiltIn {
                            Button(role: .destructive, action: {
                                Task {
                                    await AgentRegistry.shared.deleteAgent(id: metadata.id)
                                }
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                            .help("Delete custom agent")
                        }
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 8)
        .opacity(metadata.isEnabled ? 1.0 : 0.5)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.executable, .unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    metadata.executablePath = url.path
                    Task {
                        await AgentRegistry.shared.updateAgent(metadata)
                        await validateAgent()
                    }
                }
            case .failure(let error):
                errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CustomAgentFormView(
                existingMetadata: metadata,
                onSave: { updated in
                    metadata = updated
                },
                onCancel: {}
            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onAppear {
            Task {
                await validateAgent()
                canUpdate = await AgentInstaller.shared.canUpdate(metadata)
            }
        }
        .onChange(of: metadata.executablePath) { _ in
            Task {
                await validateAgent()
                canUpdate = await AgentInstaller.shared.canUpdate(metadata)
            }
        }
        .onDisappear {
            testTask?.cancel()
        }
    }

    private func validateAgent() async {
        // Use comprehensive validation that includes launch arguments and ACP protocol
        let result = await AgentRegistry.shared.validateAgentWithProtocol(named: metadata.id)
        await MainActor.run {
            isAgentValid = result.valid
            // Optionally update error message if validation failed
            if !result.valid, let error = result.error {
                errorMessage = error
            } else if result.valid {
                errorMessage = nil
            }
        }
    }

    private func updateAgent() async {
        await MainActor.run {
            isUpdating = true
            testResult = nil
        }

        do {
            // Update directly without discovery - we want to update our managed installation
            try await AgentInstaller.shared.updateAgent(metadata)

            // Get the path from registry (installer already set it during update)
            let updatedPath = AgentRegistry.shared.getAgentPath(for: metadata.id)
            await MainActor.run {
                if let path = updatedPath {
                    metadata.executablePath = path
                }
                testResult = "Updated to latest version"
            }

            // Refresh validation and canUpdate state
            await validateAgent()
            let canUpdateState = await AgentInstaller.shared.canUpdate(metadata)
            await MainActor.run {
                canUpdate = canUpdateState
            }
        } catch {
            await MainActor.run {
                testResult = "Update failed: \(error.localizedDescription)"
            }
        }

        await MainActor.run {
            isUpdating = false
        }
    }

    private func installAgent() async {
        await MainActor.run {
            isInstalling = true
            testResult = nil
        }

        do {
            // Try discovery first
            let discovered = await AgentRegistry.shared.discoverAgent(named: metadata.id)
            if let discoveredPath = discovered {
                await MainActor.run {
                    metadata.executablePath = discoveredPath
                }
                await AgentRegistry.shared.updateAgent(metadata)
            } else {
                // Install
                try await AgentInstaller.shared.installAgent(metadata)
                let path = AgentRegistry.shared.getAgentPath(for: metadata.id)
                await MainActor.run {
                    if let execPath = path {
                        metadata.executablePath = execPath
                    }
                }
            }

            // Refresh validation state
            await validateAgent()
        } catch {
            await MainActor.run {
                testResult = "Install failed: \(error.localizedDescription)"
            }
        }

        await MainActor.run {
            isInstalling = false
        }
    }

    private func testConnection() async {
        testTask?.cancel()

        isTesting = true
        testResult = nil

        guard let path = metadata.executablePath else {
            testResult = "No executable path set"
            isTesting = false
            return
        }

        testTask = Task {
            do {
                // Create temporary ACP client for testing
                let tempClient = ACPClient()

                // Launch the process with proper arguments
                try await tempClient.launch(
                    agentPath: path,
                    arguments: metadata.launchArgs
                )

                // Try to initialize - this is the real ACP validation
                let capabilities = ClientCapabilities(
                    fs: FileSystemCapabilities(
                        readTextFile: true,
                        writeTextFile: true
                    ),
                    terminal: true
                )

                _ = try await tempClient.initialize(
                    protocolVersion: 1,
                    capabilities: capabilities
                )

                // If we got here, it's a valid ACP executable
                await MainActor.run {
                    testResult = "Success: Valid ACP executable"
                }

                // Clean up
                await tempClient.terminate()
            } catch {
                await MainActor.run {
                    testResult = "Failed: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                isTesting = false
            }
        }

        await testTask?.value
    }
}
