import ACP
import SwiftUI
import UniformTypeIdentifiers

extension AgentDetailView {
    @ViewBuilder
    var commandsSection: some View {
        if metadata.isEnabled, configSpec.commandsDirectory != nil {
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
    }

    @ViewBuilder
    var mcpSection: some View {
        if metadata.isEnabled, MCPManagementStore.supportsMCPManagement(agentId: metadata.id) {
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
                        Text("Add MCP Servers")
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("MCP Servers")
            } footer: {
                Text("Attach MCP servers to new ACP sessions from Aizen without editing agent config files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
