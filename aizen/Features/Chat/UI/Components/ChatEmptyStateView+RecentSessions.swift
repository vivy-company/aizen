import ACP
import CoreData
import SwiftUI

extension ChatEmptyStateView {
    var resumeSessionSeparator: some View {
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

    var recentSessionsSection: some View {
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

    func recentSessionRow(_ session: ChatSession) -> some View {
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

    func sessionSummary(_ session: ChatSession) -> String {
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

    func sessionAgentLabel(_ session: ChatSession) -> String {
        let name = session.agentName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SessionsListStore.unknownAgentLabel : trimmed
    }

    func relativeTimestamp(for session: ChatSession) -> String {
        guard let lastMessage = session.lastMessageAt else {
            return "No messages"
        }
        return Self.recentTimestampFormatter.localizedString(for: lastMessage, relativeTo: Date())
    }

    func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    static let recentTimestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
