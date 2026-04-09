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
    let chatSessions: [ChatSession]
    let onDismiss: () -> Void
    let onSend: () -> Void

    /// Convenience initializer for backwards compatibility with markdown strings
    init(worktree: Worktree?, commentsMarkdown: String, onDismiss: @escaping () -> Void, onSend: @escaping () -> Void) {
        self.worktree = worktree
        self.attachment = .reviewComments(commentsMarkdown)
        self.chatSessions = Self.activeChatSessions(for: worktree)
        self.onDismiss = onDismiss
        self.onSend = onSend
    }

    /// Primary initializer with explicit attachment type
    init(worktree: Worktree?, attachment: ChatAttachment, onDismiss: @escaping () -> Void, onSend: @escaping () -> Void) {
        self.worktree = worktree
        self.attachment = attachment
        self.chatSessions = Self.activeChatSessions(for: worktree)
        self.onDismiss = onDismiss
        self.onSend = onSend
    }

    @State var selectedOption: SendOption?

    var availableAgents: [AgentMetadata] {
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

    static func activeChatSessions(for worktree: Worktree?) -> [ChatSession] {
        guard let worktree else { return [] }
        return Array(WorktreeSessionSnapshotBuilder.chatSessions(for: worktree).reversed())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GitWindowDivider()
            content
            GitWindowDivider()
            footer
        }
        .frame(width: 340, height: 400)
    }

    private var header: some View {
        DetailHeaderBar(
            showsBackground: false,
            padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        ) {
            Text(String(localized: "git.sendToAgent.title"))
                .font(.system(size: 14, weight: .semibold))
        } trailing: {
            DetailCloseButton(action: onDismiss, size: 16)
        }
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
}

// MARK: - Notification Extension

extension Notification.Name {
    static let sendMessageToChat = Notification.Name("sendMessageToChat")
    static let switchToChat = Notification.Name("switchToChat")
}
