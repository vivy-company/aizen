//
//  ChatEmptyStateView+Shell.swift
//  aizen
//

import SwiftUI

extension ChatEmptyStateView {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            emptyStateHeader
            agentSelectionSection

            if !recentSessions.isEmpty {
                resumeSessionSeparator
                recentSessionsSection
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaceTheme.backgroundColor())
    }

    private var emptyStateHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("chat.noChatSessions", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("chat.startConversation", bundle: .main)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var agentSelectionSection: some View {
        if enabledAgents.count + 1 <= 5 {
            HStack(spacing: 10) {
                ForEach(enabledAgents, id: \.id) { agentMetadata in
                    agentButton(for: agentMetadata)
                }
                registryButton
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack {
                Spacer(minLength: 0)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56, maximum: 64), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(enabledAgents, id: \.id) { agentMetadata in
                        agentButton(for: agentMetadata)
                    }
                    registryButton
                }
                .frame(maxWidth: 420)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func agentButton(for agentMetadata: AgentMetadata) -> some View {
        Button {
            onAgentSelect(agentMetadata.id)
        } label: {
            AgentIconView(metadata: agentMetadata, size: 14)
                .frame(width: 54, height: 54)
                .background {
                    emptyStateItemBackground(cornerRadius: 12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(emptyStateItemStrokeColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var registryButton: some View {
        Button {
            RegistryAgentsWindowController.shared.show()
        } label: {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, height: 54)
                .background {
                    emptyStateItemBackground(cornerRadius: 12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            emptyStateItemStrokeColor,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }
        }
        .buttonStyle(.plain)
        .help("Add agent from registry")
    }
}
