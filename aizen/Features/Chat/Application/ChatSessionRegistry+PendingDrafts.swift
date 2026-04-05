//
//  ChatSessionRegistry+PendingDrafts.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import Foundation

@MainActor
extension ChatSessionRegistry {
    // MARK: - Pending Messages

    func setPendingMessage(_ message: String, for chatSessionId: UUID) {
        pendingMessages[chatSessionId] = message
        touch(chatSessionId)
        evictIfNeeded()
    }

    func consumePendingMessage(for chatSessionId: UUID) -> String? {
        pendingMessages.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Input Text

    func setPendingInputText(_ text: String, for chatSessionId: UUID) {
        pendingInputText[chatSessionId] = text
        touch(chatSessionId)
        evictIfNeeded()
    }

    func consumePendingInputText(for chatSessionId: UUID) -> String? {
        pendingInputText.removeValue(forKey: chatSessionId)
    }

    func getDraftInputText(for chatSessionId: UUID) -> String? {
        pendingInputText[chatSessionId]
    }

    func clearDraftInputText(for chatSessionId: UUID) {
        pendingInputText.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Attachments

    func setPendingAttachments(_ attachments: [ChatAttachment], for chatSessionId: UUID) {
        pendingAttachments[chatSessionId] = attachments
        touch(chatSessionId)
        evictIfNeeded()
    }

    func consumePendingAttachments(for chatSessionId: UUID) -> [ChatAttachment]? {
        pendingAttachments.removeValue(forKey: chatSessionId)
    }
}
