import SwiftUI

extension SettingsView {
    var sidebarView: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("General", systemImage: "gear")
                    .tag(SettingsSelection.general)

                Label("Appearance", systemImage: "paintpalette")
                    .tag(SettingsSelection.appearance)

                Label("Transcription", systemImage: "waveform")
                    .tag(SettingsSelection.transcription)

                Label("Git", systemImage: "arrow.triangle.branch")
                    .tag(SettingsSelection.git)

                Label("Terminal", systemImage: "terminal")
                    .tag(SettingsSelection.terminal)

                Label("Editor", systemImage: "doc.text")
                    .tag(SettingsSelection.editor)

                Section("Agents") {
                    ForEach(agents, id: \.id) { agent in
                        agentRow(for: agent)
                    }

                    Button {
                        RegistryAgentsWindowController.shared.show()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.square.on.square")
                                .foregroundStyle(.secondary)
                            Text("Add From Registry")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingAddCustomAgent = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                            Text("Add Custom Agent")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, maxHeight: .infinity)
            .navigationSplitViewColumnWidth(220)
            .removingSidebarToggle()

            Divider()

            proSidebarRow
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    func agentRow(for agent: AgentMetadata) -> some View {
        HStack(spacing: 8) {
            AgentIconView(metadata: agent, size: 20)
            Text(agent.name)
            Spacer()
            if agent.id == defaultACPAgent {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .tag(SettingsSelection.agent(agent.id))
        .contextMenu {
            if agent.id != defaultACPAgent {
                Button("Make Default") {
                    defaultACPAgent = agent.id
                }
            }
        }
    }
}
