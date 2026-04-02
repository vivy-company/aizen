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

    private var resumeSessionSeparator: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
            Text("Or resume a recent session")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .frame(width: 420)
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Recent Sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Show more") {
                    onShowMore()
                }
                .buttonStyle(.link)
            }

            VStack(spacing: 8) {
                ForEach(Array(recentSessions.prefix(recentSessionsLimit)), id: \.objectID) { session in
                    Button {
                        onResumeRecentSession(session)
                    } label: {
                        recentSessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
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

    private func recentSessionRow(_ session: ChatSession) -> some View {
        let summary = sessionSummary(session)
        let agentName = sessionAgentLabel(session)
        let timestamp = relativeTimestamp(for: session)

        return HStack(spacing: 10) {
            AgentIconView(agent: session.agentName ?? AgentRegistry.defaultAgentID, size: 14)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(agentName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timestamp)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            emptyStateItemBackground(cornerRadius: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(emptyStateItemStrokeColor, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func emptyStateItemBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.white.opacity(0.001))
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.thinMaterial)
        }
    }

    private var emptyStateItemStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    private func sessionSummary(_ session: ChatSession) -> String {
        guard let messages = session.messages as? Set<ChatMessage> else {
            return "Untitled Session"
        }

        let latestUser = messages
            .filter { $0.role == "user" }
            .sorted { (m1, m2) -> Bool in
                let t1 = m1.timestamp ?? Date.distantPast
                let t2 = m2.timestamp ?? Date.distantPast
                return t1 > t2
            }
            .first

        if let contentJSON = latestUser?.contentJSON,
           let contentData = contentJSON.data(using: .utf8),
           let contentBlocks = try? JSONDecoder().decode([ContentBlock].self, from: contentData) {
            var textParts: [String] = []
            for block in contentBlocks {
                if case .text(let textContent) = block {
                    textParts.append(textContent.text)
                }
            }
            let text = textParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return "Empty message"
            }
            return truncate(text, limit: 80)
        }

        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return truncate(title, limit: 80)
        }

        return "Untitled Session"
    }

    private func sessionAgentLabel(_ session: ChatSession) -> String {
        let name = session.agentName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SessionsListStore.unknownAgentLabel : trimmed
    }

    private func relativeTimestamp(for session: ChatSession) -> String {
        guard let lastMessage = session.lastMessageAt else {
            return "No messages"
        }
        return Self.recentTimestampFormatter.localizedString(for: lastMessage, relativeTo: Date())
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    private static let recentTimestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
