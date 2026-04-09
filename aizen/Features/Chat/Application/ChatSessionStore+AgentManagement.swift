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
        agentSwitcher.performAgentSwitch(to: newAgent)

        if let sessionId = session.id {
            sessionManager.removeAgentSession(for: sessionId)
        }
        currentAgentSession = nil
        messages = []
        toolCalls = []

        setupAgentSession()
        pendingAgentSwitch = nil
    }

    func restartSession() {
        guard let agentSession = currentAgentSession else { return }

        let context = viewContext
        let newChatSession = ChatSession(context: context)
        newChatSession.id = UUID()
        newChatSession.agentName = selectedAgent
        newChatSession.createdAt = Date()
        newChatSession.worktree = worktree

        Task {
            let displayName = AgentRegistry.shared.getMetadata(for: selectedAgent)?.name ?? selectedAgent.capitalized
            newChatSession.title = displayName

            do {
                try context.save()

                await agentSession.close()

                if let oldSessionId = session.id {
                    sessionManager.removeAgentSession(for: oldSessionId)
                }

                NotificationCenter.default.post(
                    name: .switchToChatSession,
                    object: nil,
                    userInfo: ["chatSessionId": newChatSession.id!]
                )

                let worktreePath = worktree.path ?? ""
                let freshAgentSession = ChatAgentSession(agentName: selectedAgent, workingDirectory: worktreePath)
                sessionManager.setAgentSession(freshAgentSession, for: newChatSession.id!, worktreeName: worktree.branch)
                currentAgentSession = freshAgentSession
                autocompleteHandler.agentSession = freshAgentSession

                messages = []
                toolCalls = []

                setupSessionObservers(session: freshAgentSession)

                try await freshAgentSession.start(
                    agentName: selectedAgent,
                    workingDir: worktreePath,
                    chatSessionId: self.session.id
                )
            } catch {
                context.delete(newChatSession)
                do {
                    try context.save()
                } catch {
                    logger.error("Failed to rollback new session creation: \(error.localizedDescription)")
                }
                logger.error("Failed to create/start new session: \(error.localizedDescription)")
            }
        }
    }
}
