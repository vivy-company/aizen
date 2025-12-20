//
//  ChatSessionManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

@MainActor
class ChatSessionManager {
    static let shared = ChatSessionManager()

    private var agentSessions: [UUID: AgentSession] = [:]
    private var pendingMessages: [UUID: String] = [:]
    private var pendingInputText: [UUID: String] = [:]
    private var pendingAttachments: [UUID: [ChatAttachment]] = [:]
    private var sessionOrder: [UUID] = []
    private let maxCachedSessions = 20

    private init() {}

    func getAgentSession(for chatSessionId: UUID) -> AgentSession? {
        if let session = agentSessions[chatSessionId] {
            touch(chatSessionId)
            return session
        }
        return nil
    }

    func setAgentSession(_ session: AgentSession, for chatSessionId: UUID) {
        agentSessions[chatSessionId] = session
        touch(chatSessionId)
        evictIfNeeded()
    }

    func removeAgentSession(for chatSessionId: UUID) {
        if let session = agentSessions.removeValue(forKey: chatSessionId) {
            // Ensure background tasks/processes are terminated to avoid leaks.
            Task { await session.close() }
        }
        cleanupPendingData(for: chatSessionId)
        sessionOrder.removeAll { $0 == chatSessionId }
    }

    private func touch(_ chatSessionId: UUID) {
        sessionOrder.removeAll { $0 == chatSessionId }
        sessionOrder.append(chatSessionId)
    }

    private func evictIfNeeded() {
        while agentSessions.count > maxCachedSessions,
              let oldest = sessionOrder.first {
            sessionOrder.removeFirst()
            if let session = agentSessions.removeValue(forKey: oldest) {
                Task { await session.close() }
            }
            cleanupPendingData(for: oldest)
        }
    }

    private func cleanupPendingData(for chatSessionId: UUID) {
        pendingMessages.removeValue(forKey: chatSessionId)
        pendingInputText.removeValue(forKey: chatSessionId)
        pendingAttachments.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Messages

    func setPendingMessage(_ message: String, for chatSessionId: UUID) {
        pendingMessages[chatSessionId] = message
        touch(chatSessionId)
        evictIfNeeded()
    }

    func consumePendingMessage(for chatSessionId: UUID) -> String? {
        return pendingMessages.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Input Text (for prefilling input field without auto-sending)

    func setPendingInputText(_ text: String, for chatSessionId: UUID) {
        pendingInputText[chatSessionId] = text
        touch(chatSessionId)
        evictIfNeeded()
    }

    func consumePendingInputText(for chatSessionId: UUID) -> String? {
        return pendingInputText.removeValue(forKey: chatSessionId)
    }

    // MARK: - Pending Attachments

    func setPendingAttachments(_ attachments: [ChatAttachment], for chatSessionId: UUID) {
        pendingAttachments[chatSessionId] = attachments
        touch(chatSessionId)
        evictIfNeeded()
    }

    func consumePendingAttachments(for chatSessionId: UUID) -> [ChatAttachment]? {
        return pendingAttachments.removeValue(forKey: chatSessionId)
    }
}
