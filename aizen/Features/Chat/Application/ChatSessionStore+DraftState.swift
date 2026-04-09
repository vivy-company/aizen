//
//  ChatSessionStore+DraftState.swift
//  aizen
//
//  Draft and pending-input bootstrap support for chat sessions.
//

import Foundation
import SwiftUI
import os

@MainActor
extension ChatSessionStore {
    private static let draftPersistDelay = Duration.milliseconds(300)

    func persistDraftState(inputText: String) {
        guard let sessionId = session.id else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sessionManager.setPendingInputText(inputText, for: sessionId)
        }
        if !attachments.isEmpty {
            sessionManager.setPendingAttachments(attachments, for: sessionId)
        }
    }

    func loadDraftInputText() -> String? {
        guard let sessionId = session.id else { return nil }
        return sessionManager.getDraftInputText(for: sessionId)
    }

    func debouncedPersistDraft(inputText: String) {
        draftPersistTask?.cancel()
        draftPersistTask = Task { @MainActor in
            try? await Task.sleep(for: Self.draftPersistDelay)
            guard !Task.isCancelled else { return }
            guard let sessionId = session.id else { return }
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                sessionManager.clearDraftInputText(for: sessionId)
            } else {
                sessionManager.setPendingInputText(inputText, for: sessionId)
            }
        }
    }

    func sendPendingMessageIfNeeded() async {
        guard let sessionId = session.id,
              let pendingMessage = sessionManager.consumePendingMessage(for: sessionId),
              let agentSession = currentAgentSession else {
            return
        }

        do {
            try await agentSession.sendMessage(content: pendingMessage)
        } catch {
            logger.error("Failed to send pending message: \(error.localizedDescription)")
        }
    }

    func loadPendingAttachmentsIfNeeded() {
        guard let sessionId = session.id,
              let pendingAttachments = sessionManager.consumePendingAttachments(for: sessionId) else {
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            attachments.append(contentsOf: pendingAttachments)
        }
    }
}
