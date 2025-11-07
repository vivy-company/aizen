//
//  AgentSelectorMenu.swift
//  aizen
//
//  Agent selection menu component
//

import SwiftUI

struct AgentSelectorMenu: View {
    let selectedAgent: String
    let onAgentSelect: (String) -> Void

    @State private var enabledAgents: [AgentMetadata] = []
    @State private var selectedAgentMetadata: AgentMetadata?

    var body: some View {
        Menu {
            ForEach(enabledAgents, id: \.id) { agentMetadata in
                Button {
                    onAgentSelect(agentMetadata.id)
                } label: {
                    HStack {
                        AgentIconView(metadata: agentMetadata, size: 14)
                        Text(agentMetadata.name)
                        Spacer()
                        if agentMetadata.id == selectedAgent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                AgentIconView(agent: selectedAgent, size: 12)
                Text(selectedAgentMetadata?.name ?? selectedAgent.capitalized)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .task {
            await loadAgents()
        }
        .onChange(of: selectedAgent) { _ in
            Task {
                await loadSelectedAgentMetadata()
            }
        }
    }

    private func loadAgents() async {
        enabledAgents = await AgentRegistry.shared.getEnabledAgents()
        await loadSelectedAgentMetadata()
    }

    private func loadSelectedAgentMetadata() async {
        selectedAgentMetadata = AgentRegistry.shared.getMetadata(for: selectedAgent)
    }
}
