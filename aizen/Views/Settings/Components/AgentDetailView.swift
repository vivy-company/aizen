//
//  AgentDetailView.swift
//  aizen
//
//  Agent detail view for Settings sidebar
//

import SwiftUI
import UniformTypeIdentifiers

struct AgentDetailView: View {
    @Binding var metadata: AgentMetadata
    let isDefault: Bool
    let onSetDefault: () -> Void

    @State private var isInstalling = false
    @State private var isUpdating = false
    @State private var isTesting = false
    @State private var canUpdate = false
    @State private var isAgentValid = false
    @State private var testResult: String?
    @State private var showingFilePicker = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var testTask: Task<Void, Never>?
    @State private var resultDismissTask: Task<Void, Never>?
    @State private var authMethodName: String?
    @State private var showingAuthClearedMessage = false
    @State private var installedVersion: String?
    @State private var showingRulesEditor = false
    @State private var showingConfigEditor = false
    @State private var selectedConfigFile: AgentConfigFile?
    @State private var rulesPreview: String?
    @State private var commands: [AgentCommand] = []
    @State private var showingCommandEditor = false
    @State private var selectedCommand: AgentCommand?
    @State private var showingMCPMarketplace = false
    @State private var mcpServerToRemove: MCPInstalledServer?
    @State private var showingMCPRemoveConfirmation = false
    @State private var showingUsageDetails = false
    @ObservedObject private var mcpManager = MCPManager.shared
    @ObservedObject private var usageStore = AgentUsageStore.shared
    @ObservedObject private var usageMetricsStore = AgentUsageMetricsStore.shared

    private var configSpec: AgentConfigSpec {
        AgentConfigRegistry.spec(for: metadata.id)
    }

    private var supportsUsageMetrics: Bool {
        switch UsageProvider.fromAgentId(metadata.id) {
        case .codex, .claude, .gemini:
            return true
        default:
            return false
        }
    }

    var body: some View {
        Form {
            // MARK: - Agent Info

            Section {
                HStack(spacing: 12) {
                    AgentIconView(metadata: metadata, size: 32)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(metadata.name)
                                .font(.title2)
                                .fontWeight(.semibold)

                            if let version = installedVersion {
                                Text(version)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
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
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { metadata.isEnabled },
                        set: { newValue in
                            let wasEnabled = metadata.isEnabled
                            metadata.isEnabled = newValue
                            Task {
                                await AgentRegistry.shared.updateAgent(metadata)

                                if wasEnabled && !newValue {
                                    let defaultAgent = UserDefaults.standard.string(forKey: "defaultACPAgent") ?? "claude"
                                    if defaultAgent == metadata.id {
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
                }
            }

            if metadata.isEnabled {
                // MARK: - Default Status

                Section {
                    HStack {
                        Label {
                            Text(isDefault ? "This is the default agent" : "Set as default agent")
                        } icon: {
                            Circle()
                                .fill(isDefault ? .blue : .secondary.opacity(0.3))
                                .frame(width: 10, height: 10)
                        }

                        Spacer()

                        if !isDefault {
                            Button("Make Default") {
                                onSetDefault()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // MARK: - Executable Path

                if metadata.canEditPath {
                    Section("Executable") {
                        HStack(spacing: 8) {
                            TextField("Path", text: Binding(
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

                        if !metadata.launchArgs.isEmpty {
                            Text("Launch arguments: \(metadata.launchArgs.joined(separator: " "))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Authentication

                Section("Authentication") {
                    HStack {
                        Text(authMethodName ?? "Not configured")
                            .foregroundColor(authMethodName != nil ? .primary : .secondary)

                        Spacer()

                        if authMethodName != nil {
                            Button("Change") {
                                AgentRegistry.shared.clearAuthPreference(for: metadata.id)
                                loadAuthStatus()
                                showingAuthClearedMessage = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if showingAuthClearedMessage {
                        Text("Auth cleared. New chat sessions will prompt for authentication.")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                // MARK: - Usage

                if supportsUsageMetrics {
                    Section("Usage") {
                        AgentUsageSummaryView(
                            report: usageMetricsStore.report(for: metadata.id),
                            refreshState: usageMetricsStore.refreshState(for: metadata.id),
                            onRefresh: { usageMetricsStore.refresh(agentId: metadata.id, force: true) },
                            onOpenDetails: { showingUsageDetails = true }
                        )
                    }
                }

                // MARK: - Configuration

                if !configSpec.configFiles.isEmpty {
                    Section("Configuration") {
                        // Rules file
                        if let rulesFile = configSpec.rulesFile {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rulesFile.name)
                                            .font(.headline)
                                        if let desc = rulesFile.description {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button(rulesFile.exists ? "Edit" : "Create") {
                                        showingRulesEditor = true
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let preview = rulesPreview, !preview.isEmpty {
                                    Text(preview)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }

                        // Settings files
                        ForEach(configSpec.settingsFiles) { configFile in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(configFile.name)
                                        .font(.headline)
                                    if let desc = configFile.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Button(configFile.exists ? "Edit" : "Create") {
                                    selectedConfigFile = configFile
                                    showingConfigEditor = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                    }
                }

                // MARK: - Custom Commands

                if configSpec.commandsDirectory != nil {
                    Section {
                        ForEach(commands) { command in
                            HStack {
                                Image(systemName: "terminal")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)

                                Text("/\(command.name)")
                                    .font(.system(.body, design: .monospaced))

                                Spacer()

                                Button("Edit") {
                                    selectedCommand = command
                                    showingCommandEditor = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Button {
                            selectedCommand = nil
                            showingCommandEditor = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Add Command")
                            }
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Custom Commands")
                    } footer: {
                        Text("Slash commands available in chat sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - MCP Servers

                if MCPManager.supportsMCPManagement(agentId: metadata.id) {
                    Section {
                        if mcpManager.isSyncingServers(for: metadata.id) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading MCP servers...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(mcpManager.servers(for: metadata.id)) { server in
                                MCPInstalledServerRow(server: server) {
                                    mcpServerToRemove = server
                                    showingMCPRemoveConfirmation = true
                                }
                            }
                        }

                        Button {
                            showingMCPMarketplace = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Browse MCP Servers")
                            }
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("MCP Servers")
                    } footer: {
                        Text("Extend agent capabilities with MCP servers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Danger Zone (custom agents only)

                if !metadata.isBuiltIn {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Delete Agent")
                                    .font(.headline)
                                Text("Remove this custom agent from settings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Delete", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                            .buttonStyle(.bordered)
                        }
                    } header: {
                        Text("Danger Zone")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            if let result = testResult {
                HStack {
                    Image(systemName: result.contains("Success") || result.contains("Updated") ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(result)
                }
                .font(.callout)
                .foregroundColor(result.contains("Success") || result.contains("Updated") ? .green : .red)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
            }
        }
        .toolbar {
            // Install button
            if metadata.isBuiltIn,
               metadata.installMethod != nil,
               !isAgentValid,
               !isUpdating {
                ToolbarItem(placement: .primaryAction) {
                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task { await installAgent() }
                        } label: {
                            Label("Install", systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                        .help("Install agent")
                    }
                }
            }

            // Update button
            if canUpdate && (isAgentValid || isUpdating) {
                ToolbarItem(placement: .primaryAction) {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task { await updateAgent() }
                        } label: {
                            Label("Update", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                        .help("Update to latest version")
                    }
                }
            }

            // Test Connection button
            if isAgentValid {
                ToolbarItem(placement: .primaryAction) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            Label("Test", systemImage: "antenna.radiowaves.left.and.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .help("Test connection")
                    }
                }
            }

            // Spacer
            ToolbarItem(placement: .primaryAction) {
                Spacer()
                    .frame(width: 8)
            }

            // Edit button for custom agents only
            if !metadata.isBuiltIn {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Edit agent")
                }
            }
        }
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
        .alert("Delete Agent", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await AgentRegistry.shared.deleteAgent(id: metadata.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(metadata.name)\"? This cannot be undone.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .task(id: metadata.executablePath) {
            await validateAgent()
            canUpdate = await AgentInstaller.shared.canUpdate(metadata)
            loadAuthStatus()
            await loadVersion()
            loadRulesPreview()
            loadCommands()
            await mcpManager.syncInstalled(agentId: metadata.id, agentPath: metadata.executablePath)
        }
        .task(id: metadata.id) {
            if supportsUsageMetrics {
                usageMetricsStore.refreshIfNeeded(agentId: metadata.id)
            }
        }
        .sheet(isPresented: $showingRulesEditor) {
            if let rulesFile = configSpec.rulesFile {
                AgentRulesEditorSheet(
                    configFile: rulesFile,
                    agentName: metadata.name,
                    onDismiss: { loadRulesPreview() }
                )
            }
        }
        .sheet(isPresented: $showingConfigEditor) {
            if let configFile = selectedConfigFile {
                AgentConfigEditorSheet(
                    configFile: configFile,
                    agentName: metadata.name
                )
            }
        }
        .sheet(isPresented: $showingCommandEditor) {
            AgentCommandEditorSheet(
                command: selectedCommand,
                commandsDirectory: configSpec.expandedCommandsDirectory ?? "",
                agentName: metadata.name,
                onDismiss: { loadCommands() }
            )
        }
        .sheet(isPresented: $showingUsageDetails) {
            AgentUsageSheet(agentId: metadata.id, agentName: metadata.name)
        }
        .sheet(isPresented: $showingMCPMarketplace) {
            MCPMarketplaceView(
                agentId: metadata.id,
                agentPath: metadata.executablePath,
                agentName: metadata.name
            )
        }
        .alert("Remove MCP Server", isPresented: $showingMCPRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                mcpServerToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let server = mcpServerToRemove {
                    Task {
                        try? await mcpManager.remove(
                            serverName: server.serverName,
                            agentId: metadata.id,
                            agentPath: metadata.executablePath
                        )
                        mcpServerToRemove = nil
                    }
                }
            }
        } message: {
            if let server = mcpServerToRemove {
                Text("Remove \(server.displayName) from \(metadata.name)?")
            }
        }
        .onDisappear {
            testTask?.cancel()
        }
    }

    // MARK: - Private Methods

    private func validateAgent() async {
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
            try await AgentInstaller.shared.updateAgent(metadata)
            let updatedPath = AgentRegistry.shared.getAgentPath(for: metadata.id)
            await MainActor.run {
                if let path = updatedPath {
                    metadata.executablePath = path
                }
                showResult("Updated to latest version")
            }

            await validateAgent()
            let canUpdateState = await AgentInstaller.shared.canUpdate(metadata)
            await MainActor.run {
                canUpdate = canUpdateState
            }

            await AgentVersionChecker.shared.clearCache(for: metadata.id)
            await loadVersion()
        } catch {
            await MainActor.run {
                showResult("Update failed: \(error.localizedDescription)", autoDismiss: false)
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
            try await AgentInstaller.shared.installAgent(metadata)
            let path = AgentRegistry.shared.getAgentPath(for: metadata.id)
            await MainActor.run {
                if let execPath = path {
                    metadata.executablePath = execPath
                }
            }

            await validateAgent()
            let canUpdateState = await AgentInstaller.shared.canUpdate(metadata)
            await MainActor.run {
                canUpdate = canUpdateState
            }

            await loadVersion()
        } catch {
            await MainActor.run {
                showResult("Install failed: \(error.localizedDescription)", autoDismiss: false)
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
            showResult("No executable path set", autoDismiss: false)
            isTesting = false
            return
        }

        testTask = Task {
            do {
                let tempClient = ACPClient()

                try await tempClient.launch(
                    agentPath: path,
                    arguments: metadata.launchArgs
                )

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

                await MainActor.run {
                    showResult("Success: Valid ACP executable")
                }

                await tempClient.terminate()
            } catch {
                await MainActor.run {
                    showResult("Failed: \(error.localizedDescription)", autoDismiss: false)
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

    private func showResult(_ message: String, autoDismiss: Bool = true) {
        resultDismissTask?.cancel()
        testResult = message

        if autoDismiss {
            resultDismissTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    testResult = nil
                }
            }
        }
    }

    private func loadRulesPreview() {
        guard let rulesFile = configSpec.rulesFile else {
            rulesPreview = nil
            return
        }

        let path = rulesFile.expandedPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            rulesPreview = nil
            return
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            rulesPreview = nil
        } else {
            let lines = trimmed.components(separatedBy: .newlines)
            let previewLines = lines.prefix(5).joined(separator: "\n")
            rulesPreview = previewLines
        }
    }

    private func loadCommands() {
        guard let commandsDir = configSpec.expandedCommandsDirectory else {
            commands = []
            return
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: commandsDir),
              let files = try? fm.contentsOfDirectory(atPath: commandsDir) else {
            commands = []
            return
        }

        commands = files
            .filter { $0.hasSuffix(".md") }
            .map { filename in
                let name = String(filename.dropLast(3)) // Remove .md
                let path = (commandsDir as NSString).appendingPathComponent(filename)
                return AgentCommand(name: name, path: path)
            }
            .sorted { $0.name < $1.name }
    }
}
