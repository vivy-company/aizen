//
//  ChatSessionStore+AgentManagement.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import ACP
import Combine
import CoreData
import Foundation
import os.log

@MainActor
extension ChatSessionStore {
    func cycleModeForward() {
        guard let session = currentAgentSession else { return }
        let modes = session.availableModes
        guard !modes.isEmpty else { return }

        if let currentIndex = modes.firstIndex(where: { $0.id == session.currentModeId }) {
            let nextIndex = (currentIndex + 1) % modes.count
            Task {
                try? await session.setModeById(modes[nextIndex].id)
            }
        }
    }

    func requestAgentSwitch(to newAgent: String) {
        guard newAgent != selectedAgent else { return }
        pendingAgentSwitch = newAgent
        showingAgentSwitchWarning = true
    }

    func performAgentSwitch(to newAgent: String) {
        pendingAgentSwitch = nil
        createFreshSession(agentName: newAgent)
    }

    func restartSession() {
        createFreshSession(agentName: selectedAgent)
    }

    private func createFreshSession(agentName: String) {
        let context = viewContext
        let newChatSession = ChatSession(context: context)
        newChatSession.id = UUID()
        newChatSession.agentName = agentName
        newChatSession.createdAt = Date()
        newChatSession.worktree = worktree

        let displayName = AgentRegistry.shared.getMetadata(for: agentName)?.name ?? agentName.capitalized
        newChatSession.title = displayName

        do {
            try context.save()

            if let oldSessionId = session.id {
                sessionManager.removeAgentSession(for: oldSessionId)
            }

            if let newSessionId = newChatSession.id {
                NotificationCenter.default.post(
                    name: .switchToChatSession,
                    object: nil,
                    userInfo: ["chatSessionId": newSessionId]
                )
            }
        } catch {
            context.delete(newChatSession)
            logger.error("Failed to create new session: \(error.localizedDescription)")
        }
    }
}
