//  ModelSelectorMenu.swift
//  aizen
//
//  Model and agent selection menu component
//

import ACP
import SwiftUI

struct ModelSelectorMenu: View {
    let availableModels: [ModelInfo]
    let currentModelId: String?
    let isStreaming: Bool
    let selectedAgent: String
    let onModelSelect: (String) -> Void
    var showsBackground: Bool = true
    var showsIcon: Bool = true

    @ObservedObject private var agentCatalog = AgentCatalogStore.shared

    private var selectedAgentMetadata: AgentMetadata? {
        agentCatalog.metadata(for: selectedAgent)
    }

    var body: some View {
        Menu {
            // Current agent models section
            if !availableModels.isEmpty {
                Section {
                    ForEach(availableModels, id: \.modelId) { modelInfo in
                        Button {
                            onModelSelect(modelInfo.modelId)
                        } label: {
                            HStack {
                                Text(modelInfo.name)
                                Spacer()
                                if modelInfo.modelId == currentModelId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Label {
                        Text(selectedAgentMetadata?.name ?? selectedAgent.capitalized)
                    } icon: {
                        AgentIconView(agent: selectedAgent, size: 14)
                    }
                }
            }

        } label: {
            AgentMenuLabel(
                agentId: selectedAgent,
                title: currentModelName,
                showsIcon: showsIcon,
                showsBackground: showsBackground,
                titleFontSize: showsBackground ? 11 : 13,
                iconSize: showsBackground ? 12 : 13,
                chevronSize: showsBackground ? 8 : 10
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(isStreaming)  // Prevent model/agent changes during streaming
        .opacity(isStreaming ? 0.5 : 1.0)
    }

    private var currentModelName: String {
        if let currentModel = availableModels.first(where: { $0.modelId == currentModelId }) {
            return currentModel.name
        }
        return selectedAgentMetadata?.name ?? selectedAgent.capitalized
    }
}
