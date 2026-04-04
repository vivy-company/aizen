//
//  SessionRowView.swift
//  aizen
//
//  Row view for an individual chat session in the sessions list
//

import ACP
import SwiftUI

struct SessionRowView: View {
    let session: ChatSession

    @State private var cachedSummary: String = ""
    @State private var isHovered = false

    private static let timestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var relativeTimestamp: String {
        guard let lastMessage = session.lastMessageAt else {
            return "No messages"
        }
        return Self.timestampFormatter.localizedString(for: lastMessage, relativeTo: Date())
    }

    private var agentName: String {
        let name = session.agentName ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SessionsListStore.unknownAgentLabel : trimmed
    }

    private var sessionTitle: String {
        if !cachedSummary.isEmpty {
            return cachedSummary
        }
        if let title = session.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return "Untitled Session"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AgentIconView(agent: session.agentName ?? AgentRegistry.defaultAgentID, size: 18)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(sessionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Text(relativeTimestamp)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Text(agentName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if session.archived {
                        TagBadge(text: "Archived", color: .orange, cornerRadius: 4, backgroundOpacity: 0.2)
                    }

                    Text("•")
                        .foregroundStyle(.quaternary)

                    Text("\(session.messageCount) messages")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let worktreeName = session.worktree?.branch {
                        Text("•")
                            .foregroundStyle(.quaternary)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text(worktreeName)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }

                    if let createdAt = session.createdAt {
                        Text("•")
                            .foregroundStyle(.quaternary)

                        Text("Created \(createdAt, formatter: Self.dateFormatter)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(SelectableRowModifier(
            isSelected: false,
            isHovered: isHovered,
            showsIdleBackground: false,
            cornerRadius: 0
        ))
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: session.id) {
            cachedSummary = SessionRowSummaryBuilder.summary(for: session)
        }
    }
}
