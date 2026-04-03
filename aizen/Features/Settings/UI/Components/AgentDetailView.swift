//
//  AgentDetailView.swift
//  aizen
//
//  Agent detail view for Settings sidebar
//

import ACP
import SwiftUI
import UniformTypeIdentifiers

struct AgentDetailView: View {
    @Binding var metadata: AgentMetadata
    let isDefault: Bool
    let onSetDefault: () -> Void

    @State var isInstalling = false
    @State var isUpdating = false
    @State var isTesting = false
    @State var canUpdate = false
    @State var isAgentValid = false
    @State var testResult: String?
    @State var showingFilePicker = false
    @State var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State var errorMessage: String?
    @State var testTask: Task<Void, Never>?
    @State var resultDismissTask: Task<Void, Never>?
    @State var authMethodName: String?
    @State var showingAuthClearedMessage = false
    @State var installedVersion: String?
    @State var showingRulesEditor = false
    @State var showingConfigEditor = false
    @State var selectedConfigFile: AgentConfigFile?
    @State var rulesPreview: String?
    @State var commands: [AgentCommand] = []
    @State var showingCommandEditor = false
    @State var selectedCommand: AgentCommand?
    @State var showingMCPMarketplace = false
    @State var mcpServerToRemove: MCPInstalledServer?
    @State var showingMCPRemoveConfirmation = false
    @State var showingUsageDetails = false
    @State var environmentSaveTask: Task<Void, Never>?
    @State var environmentVariablesDraft: [AgentEnvironmentVariable] = []
    @ObservedObject var mcpManager = MCPManagementStore.shared
    @ObservedObject var usageMetricsStore = AgentUsageMetricsStore.shared

    var configSpec: AgentConfigSpec {
        AgentConfigRegistry.spec(for: metadata.id)
    }

    var supportsUsageMetrics: Bool {
        switch UsageProvider.fromAgentId(metadata.id) {
        case .codex, .claude, .gemini:
            return true
        default:
            return false
        }
    }

    var resolvedAgentPath: String? {
        AgentRegistry.shared.getAgentPath(for: metadata.id)
    }

    var resolvedLaunchArgs: [String] {
        AgentRegistry.shared.getAgentLaunchArgs(for: metadata.id)
    }

    var body: some View {
        Form {
            agentInfoSection

            defaultStatusSection

            executableSection

            authenticationSection

            AgentEnvironmentVariablesEditor(
                variables: Binding(
                    get: { environmentVariablesDraft },
                    set: { newValue in
                        environmentVariablesDraft = newValue
                        metadata.environmentVariables = newValue
                        scheduleEnvironmentSave()
                    }
                )
            )

            if metadata.isEnabled {
                usageSection

                configurationSection

                commandsSection

                mcpSection

                // MARK: - Danger Zone (custom agents only)

                if metadata.isCustom || metadata.isRegistry {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(metadata.isCustom ? "Delete Agent" : "Remove Agent")
                                    .font(.headline)
                                Text(metadata.isCustom ? "Remove this custom agent from settings" : "Remove this registry agent from settings")
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
        .settingsSurface()
        .safeAreaInset(edge: .bottom) {
            if let result = testResult {
                let isSuccess = result.contains("Success") || result.contains("Updated")
                HStack {
                    ValidationStatusIcon(isValid: isSuccess)
                    Text(result)
                }
                .font(.callout)
                .foregroundColor(isSuccess ? .green : .red)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
            }
        }
        .toolbar { toolbarContent }
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
        .task(id: AgentRegistry.shared.getAgentPath(for: metadata.id) ?? metadata.id) {
            await validateAgent()
            canUpdate = await AgentInstaller.shared.canUpdate(metadata)
            loadAuthStatus()
            await loadVersion()
            loadRulesPreview()
            loadCommands()
            await mcpManager.syncInstalled(agentId: metadata.id)
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
                agentPath: AgentRegistry.shared.getAgentPath(for: metadata.id),
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
                            agentId: metadata.id
                        )
                        mcpServerToRemove = nil
                    }
                }
            }
        } message: {
            if let server = mcpServerToRemove {
                Text("Remove \(server.displayName) from Aizen's MCP defaults for \(metadata.name)?")
            }
        }
        .task(id: metadata.id) {
            loadEnvironmentDraft()
        }
        .onDisappear {
            testTask?.cancel()
            flushEnvironmentSaveIfNeeded()
        }
    }

    // MARK: - Private Methods

}
