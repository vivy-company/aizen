//
//  ChatSessionRegistry.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Foundation
import Combine

@MainActor
class ChatSessionRegistry: ObservableObject {
    static let shared = ChatSessionRegistry()

    var agentSessions: [UUID: ChatAgentSession] = [:]

    /// Sessions with pending permission requests (for UI indicators)
    @Published var sessionsWithPendingPermissions: Set<UUID> = []

    var permissionObservers: [UUID: AnyCancellable] = [:]
    var pendingMessages: [UUID: String] = [:]
    var pendingInputText: [UUID: String] = [:]
    var pendingAttachments: [UUID: [ChatAttachment]] = [:]
    var sessionOrder: [UUID] = []
    let maxCachedSessions = 20

    private init() {}

    func getAgentSession(for chatSessionId: UUID) -> ChatAgentSession? {
        if let session = agentSessions[chatSessionId] {
            touch(chatSessionId)
            return session
        }
        return nil
    }

    func setAgentSession(_ session: ChatAgentSession, for chatSessionId: UUID, worktreeName: String? = nil) {
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

    func cleanupPendingData(for chatSessionId: UUID) {
        pendingMessages.removeValue(forKey: chatSessionId)
        pendingInputText.removeValue(forKey: chatSessionId)
        pendingAttachments.removeValue(forKey: chatSessionId)
    }
}
