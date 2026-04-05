//
//  SendToAgentSheet+Content.swift
//  aizen
//

import SwiftUI

extension SendToAgentSheet {
    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !chatSessions.isEmpty {
                    sectionHeader(String(localized: "git.sendToAgent.activeChats"))

                    ForEach(chatSessions, id: \.id) { session in
                        chatSessionRow(session)
                    }
                }

                sectionHeader(String(localized: "git.sendToAgent.startNewChat"))

                ForEach(availableAgents, id: \.name) { agent in
                    newChatRow(agent)
                }
            }
            .padding(16)
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    func chatSessionRow(_ session: ChatSession) -> some View {
        let isSelected = selectedOption == .existingChat(session.id ?? UUID())

        return Button {
            selectedOption = .existingChat(session.id ?? UUID())
        } label: {
            HStack(spacing: 10) {
                if let agentName = session.agentName {
                    AgentIconView(agent: agentName, size: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title ?? String(localized: "git.sendToAgent.chat"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    if let date = session.createdAt {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    func newChatRow(_ agent: AgentMetadata) -> some View {
        let isSelected = selectedOption == .newChat(agent.id)

        return Button {
            selectedOption = .newChat(agent.id)
        } label: {
            HStack(spacing: 10) {
                AgentIconView(agent: agent.id, size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "git.sendToAgent.newChat \(agent.name)"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(String(localized: "git.sendToAgent.startNewConversation"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
