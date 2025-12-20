//
//  ChatSessionViewModel+Messages.swift
//  aizen
//
//  Message operations for chat sessions
//

import Foundation
import SwiftUI

extension ChatSessionViewModel {
    // MARK: - Message Operations

    func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageAttachments = attachments

        // Allow sending if we have text OR attachments
        guard !messageText.isEmpty || !messageAttachments.isEmpty else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            inputText = ""
            attachments = []
            isProcessing = true
            // Re-enable auto-scroll when user sends a message
            isNearBottom = true
        }

        Task {
            do {
                guard let agentSession = self.currentAgentSession else {
                    throw NSError(domain: "ChatSessionView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No agent session"])
                }
                guard let worktreePath = self.worktree.path, !worktreePath.isEmpty else {
                    throw NSError(domain: "ChatSessionView", code: -4, userInfo: [NSLocalizedDescriptionKey: "Missing worktree path"])
                }

                // Start session if not active
                if !agentSession.isActive {
                    try await agentSession.start(agentName: self.selectedAgent, workingDir: worktreePath)
                }

                // Wait for session to be ready (not just active) - handles initialization delay
                var attempts = 0
                while !agentSession.sessionState.isReady && attempts < 100 {
                    // Check for failure state
                    if case .failed(let reason) = agentSession.sessionState {
                        throw NSError(domain: "ChatSessionView", code: -2, userInfo: [NSLocalizedDescriptionKey: "Session failed: \(reason)"])
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    attempts += 1
                }

                guard agentSession.sessionState.isReady else {
                    throw NSError(domain: "ChatSessionView", code: -3, userInfo: [NSLocalizedDescriptionKey: "Session initialization timed out"])
                }

                try await agentSession.sendMessage(content: messageText, attachments: messageAttachments)

                self.scrollToBottom()
            } catch {
                // Add error to AgentSession (messages are derived from session)
                self.currentAgentSession?.addSystemMessage(
                    String(localized: "chat.error.prefix \(error.localizedDescription)")
                )

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.rebuildTimeline()
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.attachments = messageAttachments
                    self.isProcessing = false
                }
            }
            // isProcessing is now derived from message state in setupSessionObservers
        }
    }

    func cancelCurrentPrompt() {
        Task {
            await currentAgentSession?.cancelCurrentPrompt()
        }
    }

    func loadMessages() {
        // No-op: Sessions start fresh, no persistence
    }

    // MARK: - Private Helpers

    func messageRoleFromString(_ role: String) -> MessageRole {
        switch role.lowercased() {
        case "user":
            return .user
        case "agent":
            return .agent
        default:
            return .system
        }
    }
}
