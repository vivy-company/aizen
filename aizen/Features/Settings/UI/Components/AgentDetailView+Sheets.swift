import ACP
import SwiftUI
import UniformTypeIdentifiers

extension AgentDetailView {
    @ViewBuilder
    var editSheet: some View {
        CustomAgentFormView(
            existingMetadata: metadata,
            onSave: { updated in
                metadata = updated
            },
            onCancel: {}
        )
    }

    @ViewBuilder
    var rulesEditorSheet: some View {
        if let rulesFile = configSpec.rulesFile {
            AgentRulesEditorSheet(
                configFile: rulesFile,
                agentName: metadata.name,
                onDismiss: { loadRulesPreview() }
            )
        }
    }

    @ViewBuilder
    var configEditorSheet: some View {
        if let configFile = selectedConfigFile {
            AgentConfigEditorSheet(
                configFile: configFile,
                agentName: metadata.name
            )
        }
    }

    @ViewBuilder
    var commandEditorSheet: some View {
        AgentCommandEditorSheet(
            command: selectedCommand,
            commandsDirectory: configSpec.expandedCommandsDirectory ?? "",
            agentName: metadata.name,
            onDismiss: { loadCommands() }
        )
    }

    @ViewBuilder
    var usageDetailsSheet: some View {
        AgentUsageSheet(agentId: metadata.id, agentName: metadata.name)
    }

    @ViewBuilder
    var mcpMarketplaceSheet: some View {
        MCPMarketplaceView(
            agentId: metadata.id,
            agentPath: AgentRegistry.shared.getAgentPath(for: metadata.id),
            agentName: metadata.name
        )
    }

    func deleteAgent() {
        Task {
            await AgentRegistry.shared.deleteAgent(id: metadata.id)
        }
    }

    func removeSelectedMCPServer() {
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
}
