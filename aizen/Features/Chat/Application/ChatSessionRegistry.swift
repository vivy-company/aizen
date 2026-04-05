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

    private var agentSessions: [UUID: ChatAgentSession] = [:]

    /// Sessions with pending permission requests (for UI indicators)
    @Published private(set) var sessionsWithPendingPermissions: Set<UUID> = []

    private var permissionObservers: [UUID: AnyCancellable] = [:]
    var pendingMessages: [UUID: String] = [:]
    var pendingInputText: [UUID: String] = [:]
    var pendingAttachments: [UUID: [ChatAttachment]] = [:]
    private var sessionOrder: [UUID] = []
    private let maxCachedSessions = 20

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

    private func observePermissionState(for chatSessionId: UUID, session: ChatAgentSession) {
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

    func touch(_ chatSessionId: UUID) {
        sessionOrder.removeAll { $0 == chatSessionId }
        sessionOrder.append(chatSessionId)
    }

    func evictIfNeeded() {
        while agentSessions.count > maxCachedSessions,
              let oldest = sessionOrder.first {
            sessionOrder.removeFirst()
            if let session = agentSessions.removeValue(forKey: oldest) {
                Task { await session.close() }
            }
            cleanupPendingData(for: oldest)
        }
    }

    func cleanupPendingData(for chatSessionId: UUID) {
        pendingMessages.removeValue(forKey: chatSessionId)
        pendingInputText.removeValue(forKey: chatSessionId)
        pendingAttachments.removeValue(forKey: chatSessionId)
    }
}
