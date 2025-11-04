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
        VStack(spacing: 0) {
            // Default Agent Picker at top
            VStack(spacing: 12) {
                HStack {
                    Text("Default Agent")
                        .font(.headline)

                    Spacer()

                    Picker("", selection: $defaultACPAgent) {
                        ForEach(enabledAgents, id: \.id) { agent in
                            HStack {
                                AgentIconView(metadata: agent, size: 16)
                                Text(agent.name)
                            }
                            .tag(agent.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 150)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Agent List with Add Custom Agent button
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(agents.indices, id: \.self) { index in
                        AgentListItemView(metadata: $agents[index])

                        if index < agents.count - 1 {
                            Divider()
                        }
                    }

                    // Add Custom Agent button in the list
                    Divider()

                    Button(action: { showingAddCustomAgent = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.accentColor)

                            Text("Add Custom Agent")
                                .font(.headline)

                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
        }
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
