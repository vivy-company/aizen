//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

private extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

// MARK: - Settings Selection

enum SettingsSelection: Hashable {
    case general
    case appearance
    case transcription
    case pro
    case git
    case terminal
    case editor
    case agent(String) // agent id
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("defaultEditor") var defaultEditor = "code"
    @AppStorage("defaultACPAgent") var defaultACPAgent = AgentRegistry.defaultAgentID
    @State var selection: SettingsSelection? = .general
    @State var agents: [AgentMetadata] = []
    @State private var showingAddCustomAgent = false
    @StateObject var licenseManager = LicenseStateStore.shared

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    // Static settings items
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

                    // Agents section
                    Section("Agents") {
                        ForEach(agents, id: \.id) { agent in
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
        } detail: {
            if #available(macOS 14.0, *) {
                NavigationStack {
                    detailView
                }
            } else {
                NavigationStack {
                    detailView
                }
            }
        }
        .toolbar {
            // Forces creation of an NSToolbar so the window's unified toolbar style applies.
            ToolbarItem(placement: .principal) { Text("") }
        }
        .settingsSheetChrome()
        .settingsNativeToolbarGlass()
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 500)
        .onAppear {
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPro)) { _ in
            selection = .pro
        }
        .sheet(isPresented: $showingAddCustomAgent) {
            CustomAgentFormView(
                onSave: { _ in
                    loadAgents()
                },
                onCancel: {}
            )
        }
    }

    private func loadAgents() {
        let updatedAgents = AgentRegistry.shared.getAllAgents()
        agents = updatedAgents

        if case .agent(let agentId) = selection,
           !updatedAgents.contains(where: { $0.id == agentId }) {
            selection = updatedAgents.first.map { .agent($0.id) } ?? .general
        }
    }

}
