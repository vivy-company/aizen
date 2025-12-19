//
//  AgentsSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct AgentsSettingsView: View {
    @Binding var defaultACPAgent: String

    @State private var agents: [AgentMetadata] = []
    @State private var enabledAgents: [AgentMetadata] = []
    @State private var showingAddCustomAgent = false

    var body: some View {
        Form {
            Section {
                Picker("Default Agent", selection: $defaultACPAgent) {
                    ForEach(enabledAgents, id: \.id) { agent in
                        HStack {
                            AgentIconView(metadata: agent, size: 16)
                            Text(agent.name)
                        }
                        .tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                ForEach(agents.indices, id: \.self) { index in
                    AgentListItemView(metadata: $agents[index])
                }

                Button(action: { showingAddCustomAgent = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Add Custom Agent")
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Installed Agents")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadAgents()
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
        Task {
            agents = await AgentRegistry.shared.getAllAgents()
            enabledAgents = await AgentRegistry.shared.getEnabledAgents()
        }
    }
}
