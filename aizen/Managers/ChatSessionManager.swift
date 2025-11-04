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

    private init() {}

    func getAgentSession(for chatSessionId: UUID) -> AgentSession? {
        return agentSessions[chatSessionId]
    }

    func setAgentSession(_ session: AgentSession, for chatSessionId: UUID) {
        agentSessions[chatSessionId] = session
    }

    func removeAgentSession(for chatSessionId: UUID) {
        agentSessions.removeValue(forKey: chatSessionId)
    }
}
