import ACP
import CoreData
import SwiftUI

struct ChatEmptyStateView: View {
    let enabledAgents: [AgentMetadata]
    let recentSessions: [ChatSession]
    let recentSessionsLimit: Int
    let onAgentSelect: (String) -> Void
    let onShowMore: () -> Void
    let onResumeRecentSession: (ChatSession) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

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

            if !recentSessions.isEmpty {
                resumeSessionSeparator
                recentSessionsSection
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaceTheme.backgroundColor())
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

    @ViewBuilder
    func emptyStateItemBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.white.opacity(0.001))
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.thinMaterial)
        }
    }

    var emptyStateItemStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

}
