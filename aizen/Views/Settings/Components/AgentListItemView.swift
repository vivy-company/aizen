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
    @State private var authMethodName: String?
    @State private var showingAuthClearedMessage = false
    @State private var installedVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                AgentIconView(metadata: metadata, size: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(metadata.name)
                            .font(.headline)

                        if let version = installedVersion {
                            Text(version)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

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
                                    if let newDefault = AgentRegistry.shared.getEnabledAgents().first {
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
                    // Path field - editable for custom agents only
                    if metadata.canEditPath {
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
                    }

                    // Launch args
                    if !metadata.launchArgs.isEmpty {
                        Text("Launch args: \(metadata.launchArgs.joined(separator: " "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Authentication section
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Authentication:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(authMethodName ?? "Not configured")
                                .font(.caption)
                                .foregroundColor(authMethodName != nil ? .primary : .secondary)

                            if authMethodName != nil {
                                Button("Change") {
                                    AgentRegistry.shared.clearAuthPreference(for: metadata.id)
                                    loadAuthStatus()
                                    showingAuthClearedMessage = true
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }

                        if showingAuthClearedMessage {
                            Text("Auth cleared. New chat sessions will prompt for authentication.")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
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
                                    .foregroundColor(result.contains("Success") || result.contains("Updated") ? .green : .red)
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
        .task(id: metadata.executablePath) {
            // Validate and check for updates when path changes
            await validateAgent()
            canUpdate = await AgentInstaller.shared.canUpdate(metadata)
            loadAuthStatus()
            await loadVersion()
        }
        .onDisappear {
            testTask?.cancel()
        }
    }

    private func validateAgent() async {
        // For settings, just check if the executable exists and is executable
        // Full ACP protocol validation is done via "Test Connection" button
        let isValid = AgentRegistry.shared.validateAgent(named: metadata.id)
        await MainActor.run {
            isAgentValid = isValid
            errorMessage = nil
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

            // Reload version after update
            await AgentVersionChecker.shared.clearCache(for: metadata.id)
            await loadVersion()
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
            // Install to managed .aizen/agents directory
            try await AgentInstaller.shared.installAgent(metadata)
            let path = AgentRegistry.shared.getAgentPath(for: metadata.id)
            await MainActor.run {
                if let execPath = path {
                    metadata.executablePath = execPath
                }
            }

            // Refresh validation and update state
            await validateAgent()
            let canUpdateState = await AgentInstaller.shared.canUpdate(metadata)
            await MainActor.run {
                canUpdate = canUpdateState
            }

            // Load version after install
            await loadVersion()
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
                    terminal: true,
                    meta: [
                        "terminal_output": AnyCodable(true),
                        "terminal-auth": AnyCodable(true)
                    ]
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

    private func loadAuthStatus() {
        authMethodName = AgentRegistry.shared.getAuthMethodName(for: metadata.id)
        showingAuthClearedMessage = false
    }

    private func loadVersion() async {
        guard isAgentValid else {
            await MainActor.run {
                installedVersion = nil
            }
            return
        }

        let versionInfo = await AgentVersionChecker.shared.checkVersion(for: metadata.id)
        await MainActor.run {
            installedVersion = versionInfo.current
        }
    }
}
