//  ModelSelectorMenu.swift
//  aizen
//
//  Model and agent selection menu component
//

import SwiftUI

struct ModelSelectorMenu: View {
    @ObservedObject var session: AgentSession
    let selectedAgent: String
    let onAgentSelect: (String) -> Void

    @State private var enabledAgents: [AgentMetadata] = []

    private var selectedAgentMetadata: AgentMetadata? {
        AgentRegistry.shared.getMetadata(for: selectedAgent)
    }

    private var otherAgents: [AgentMetadata] {
        enabledAgents.filter { $0.id != selectedAgent }
    }

    var body: some View {
        Menu {
            // Current agent models section
            if !session.availableModels.isEmpty {
                Section {
                    ForEach(session.availableModels, id: \.modelId) { modelInfo in
                        Button {
                            Task {
                                try? await session.setModel(modelInfo.modelId)
                            }
                        } label: {
                            HStack {
                                Text(modelInfo.name)
                                Spacer()
                                if modelInfo.modelId == session.currentModelId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Label(selectedAgentMetadata?.name ?? selectedAgent.capitalized, image: "agent-\(selectedAgent)")
                }
            }

            // Other agents section
            if !otherAgents.isEmpty {
                Section {
                    ForEach(otherAgents, id: \.id) { agentMetadata in
                        Button {
                            onAgentSelect(agentMetadata.id)
                        } label: {
                            HStack {
                                AgentIconView(metadata: agentMetadata, size: 14)
                                Text(agentMetadata.name)
                            }
                        }
                    }
                } header: {
                    Text("Change Agent")
                }
            }
        } label: {
            AgentMenuLabel(
                agentId: selectedAgent,
                title: currentModelName
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(session.isStreaming)  // Prevent model/agent changes during streaming
        .opacity(session.isStreaming ? 0.5 : 1.0)
        .help(String(localized: "chat.model.select"))
        .onAppear {
            enabledAgents = AgentRegistry.shared.getEnabledAgents()
        }
        .id(selectedAgent)
    }

    private var currentModelName: String {
        if let currentModel = session.availableModels.first(where: { $0.modelId == session.currentModelId }) {
            return currentModel.name
        }
        return selectedAgentMetadata?.name ?? selectedAgent.capitalized
    }
}
