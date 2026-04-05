//
//  ChatSessionRegistry+SessionCache.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import ACP
import Combine
import Foundation

@MainActor
extension ChatSessionRegistry {
    func observePermissionState(for chatSessionId: UUID, session: ChatAgentSession) {
        permissionObservers[chatSessionId]?.cancel()

        permissionObservers[chatSessionId] = session.permissionHandler.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                guard let self else { return }
                if showing {
                    sessionsWithPendingPermissions.insert(chatSessionId)
                } else {
                    sessionsWithPendingPermissions.remove(chatSessionId)
                }
            }
    }

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
}
