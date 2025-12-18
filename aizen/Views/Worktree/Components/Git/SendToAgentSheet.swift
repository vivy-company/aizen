//
//  SendToAgentSheet.swift
//  aizen
//
//  Sheet for selecting which agent/chat to send review comments to
//

import SwiftUI

struct SendToAgentSheet: View {
    let worktree: Worktree?
    let attachment: ChatAttachment
    let onDismiss: () -> Void
    let onSend: () -> Void

    /// Convenience initializer for backwards compatibility with markdown strings
    init(worktree: Worktree?, commentsMarkdown: String, onDismiss: @escaping () -> Void, onSend: @escaping () -> Void) {
        self.worktree = worktree
        self.attachment = .reviewComments(commentsMarkdown)
        self.onDismiss = onDismiss
        self.onSend = onSend
    }

    /// Primary initializer with explicit attachment type
    init(worktree: Worktree?, attachment: ChatAttachment, onDismiss: @escaping () -> Void, onSend: @escaping () -> Void) {
        self.worktree = worktree
        self.attachment = attachment
        self.onDismiss = onDismiss
        self.onSend = onSend
    }

    @State private var selectedOption: SendOption?

    private var chatSessions: [ChatSession] {
        guard let worktree = worktree else { return [] }
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
    }

    private var availableAgents: [AgentMetadata] {
        AgentRegistry.shared.getEnabledAgents()
    }

    enum SendOption: Identifiable, Hashable {
        case existingChat(UUID)
        case newChat(String) // agent id

        var id: String {
            switch self {
            case .existingChat(let uuid): return "existing-\(uuid.uuidString)"
            case .newChat(let agent): return "new-\(agent)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 340, height: 400)
    }

    private var header: some View {
        HStack {
            Text(String(localized: "git.sendToAgent.title"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Existing chats section
                if !chatSessions.isEmpty {
                    sectionHeader(String(localized: "git.sendToAgent.activeChats"))

                    ForEach(chatSessions, id: \.id) { session in
                        chatSessionRow(session)
                    }
                }

                // New chat section
                sectionHeader(String(localized: "git.sendToAgent.startNewChat"))

                ForEach(availableAgents, id: \.name) { agent in
                    newChatRow(agent)
                }
            }
            .padding(16)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func chatSessionRow(_ session: ChatSession) -> some View {
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

    private func newChatRow(_ agent: AgentMetadata) -> some View {
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

    private var footer: some View {
        HStack {
            Button(String(localized: "general.cancel")) {
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button(String(localized: "git.sendToAgent.send")) {
                sendToAgent()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(selectedOption == nil)
        }
        .padding(16)
    }

    private func sendToAgent() {
        guard let option = selectedOption else { return }

        switch option {
        case .existingChat(let sessionId):
            sendToExistingChat(sessionId: sessionId)
        case .newChat(let agentId):
            createNewChatAndSend(agentId: agentId)
        }

        onDismiss()
        onSend()
    }

    private func sendToExistingChat(sessionId: UUID) {
        // Set pending attachment and switch to chat
        ChatSessionManager.shared.setPendingAttachments([attachment], for: sessionId)

        // Post notification to switch to the chat
        NotificationCenter.default.post(
            name: .switchToChat,
            object: nil,
            userInfo: ["sessionId": sessionId]
        )
    }

    private func createNewChatAndSend(agentId: String) {
        guard let worktree = worktree,
              let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let displayName = AgentRegistry.shared.getMetadata(for: agentId)?.name ?? agentId.capitalized
        session.title = displayName
        session.agentName = agentId
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()

            // Post notification to switch to the new chat with attachment
            NotificationCenter.default.post(
                name: .sendMessageToChat,
                object: nil,
                userInfo: [
                    "sessionId": session.id as Any,
                    "attachment": attachment
                ]
            )
        } catch {
            print("Failed to create chat session: \(error)")
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let sendMessageToChat = Notification.Name("sendMessageToChat")
    static let switchToChat = Notification.Name("switchToChat")
}
