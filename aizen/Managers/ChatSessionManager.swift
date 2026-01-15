//
//  ChatSessionManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import Combine

@MainActor
class ChatSessionManager: ObservableObject {
    static let shared = ChatSessionManager()

    private var agentSessions: [UUID: AgentSession] = [:]

    /// Sessions with pending permission requests (for UI indicators)
    @Published private(set) var sessionsWithPendingPermissions: Set<UUID> = []

    private var permissionObservers: [UUID: AnyCancellable] = [:]
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

    func setAgentSession(_ session: AgentSession, for chatSessionId: UUID, worktreeName: String? = nil) {
        agentSessions[chatSessionId] = session
        touch(chatSessionId)
        evictIfNeeded()

        session.chatSessionId = chatSessionId
        
        // Set permission handler context for notifications
        session.permissionHandler.chatSessionId = chatSessionId
        session.permissionHandler.worktreeName = worktreeName

        // Observe permission state changes
        observePermissionState(for: chatSessionId, session: session)
    }

    private func observePermissionState(for chatSessionId: UUID, session: AgentSession) {
        // Remove existing observer
        permissionObservers[chatSessionId]?.cancel()

        // Observe showingPermissionAlert changes
        permissionObservers[chatSessionId] = session.permissionHandler.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                guard let self = self else { return }
                if showing {
                    self.sessionsWithPendingPermissions.insert(chatSessionId)
                } else {
                    self.sessionsWithPendingPermissions.remove(chatSessionId)
                }
            }
    }

    func removeAgentSession(for chatSessionId: UUID) {
        // Clean up permission observer
        permissionObservers[chatSessionId]?.cancel()
        permissionObservers.removeValue(forKey: chatSessionId)
        sessionsWithPendingPermissions.remove(chatSessionId)

        if let session = agentSessions.removeValue(forKey: chatSessionId) {
            // Ensure background tasks/processes are terminated to avoid leaks.
            Task { await session.close() }
        }
        cleanupPendingData(for: chatSessionId)
        sessionOrder.removeAll { $0 == chatSessionId }
    }

    /// Check if a session has a pending permission request
    func hasPendingPermission(for chatSessionId: UUID) -> Bool {
        sessionsWithPendingPermissions.contains(chatSessionId)
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

    /// Get draft input text without consuming it (for tab switching)
    func getDraftInputText(for chatSessionId: UUID) -> String? {
        return pendingInputText[chatSessionId]
    }

    /// Clear draft input text (call after message is sent)
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
        return pendingAttachments.removeValue(forKey: chatSessionId)
    }
}
