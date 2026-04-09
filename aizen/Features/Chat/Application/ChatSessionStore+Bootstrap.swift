//
//  ChatSessionStore+Bootstrap.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import ACP
import Foundation
import os.log
import SwiftUI

@MainActor
extension ChatSessionStore {
    func setupAgentSession() {
        guard let sessionId = session.id else { return }
        guard settingUpSessionId != sessionId else { return }
        settingUpSessionId = sessionId

        resetTimelineSyncState()
        loadPendingAttachmentsIfNeeded()
        loadHistoricalMessages()

        let worktreePath = worktree.path ?? ""
        autocompleteHandler.worktreePath = worktreePath

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            if existingSession.messages.isEmpty && !historicalMessages.isEmpty {
                existingSession.messages = historicalMessages
            }
            if existingSession.toolCalls.isEmpty && !historicalToolCalls.isEmpty {
                existingSession.loadPersistedToolCalls(historicalToolCalls)
            }

            currentAgentSession = existingSession
            autocompleteHandler.agentSession = existingSession
            updateDerivedState(from: existingSession)
            bootstrapTimelineState(from: existingSession)
            setupSessionObservers(session: existingSession)

            if !worktreePath.isEmpty {
                Task {
                    await autocompleteHandler.indexWorktree()
                }
            }

            if !existingSession.isActive {
                guard !worktreePath.isEmpty else {
                    logger.error("Chat session missing worktree path; cannot start agent session.")
                    settingUpSessionId = nil
                    return
                }

                Task { [self] in
                    defer { self.settingUpSessionId = nil }
                    do {
                        try await startOrResumeSession(existingSession, sessionId: sessionId, worktreePath: worktreePath)
                        await sendPendingMessageIfNeeded()
                    } catch {
                        self.logger.error("Failed to start session for \(self.selectedAgent): \(error.localizedDescription)")
                    }
                }
            } else {
                Task {
                    defer { self.settingUpSessionId = nil }
                    await sendPendingMessageIfNeeded()
                }
            }
            return
        }

        guard !worktreePath.isEmpty else {
            logger.error("Chat session missing worktree path; cannot start agent session.")
            settingUpSessionId = nil
            return
        }

        let newSession = ChatAgentSession(agentName: selectedAgent, workingDirectory: worktreePath)
        if !historicalMessages.isEmpty {
            newSession.messages = historicalMessages
        }
        if !historicalToolCalls.isEmpty {
            newSession.loadPersistedToolCalls(historicalToolCalls)
        }

        let worktreeName = worktree.branch ?? "Chat"
        sessionManager.setAgentSession(newSession, for: sessionId, worktreeName: worktreeName)
        currentAgentSession = newSession
        autocompleteHandler.agentSession = newSession
        updateDerivedState(from: newSession)
        bootstrapTimelineState(from: newSession)
        setupSessionObservers(session: newSession)

        Task {
            defer { self.settingUpSessionId = nil }
            await autocompleteHandler.indexWorktree()

            if !newSession.isActive {
                do {
                    try await startOrResumeSession(newSession, sessionId: sessionId, worktreePath: worktreePath)
                    await sendPendingMessageIfNeeded()
                } catch {
                    self.logger.error("Failed to start new session for \(self.selectedAgent): \(error.localizedDescription)")
                }
            } else {
                await sendPendingMessageIfNeeded()
            }
        }
    }

    func startOrResumeSession(
        _ agentSession: ChatAgentSession,
        sessionId: UUID,
        worktreePath: String
    ) async throws {
        if agentSession.isActive || agentSession.sessionState.isInitializing {
            return
        }

        if let acpSessionId = await ChatSessionPersistence.shared.getSessionId(for: sessionId, in: viewContext),
           !acpSessionId.isEmpty {
            do {
                try await agentSession.resume(
                    acpSessionId: acpSessionId,
                    agentName: selectedAgent,
                    workingDir: worktreePath,
                    chatSessionId: sessionId
                )
                return
            } catch {
                var shouldClearSessionId = true
                var shouldShowFailure = true
                var shouldAttachHistory = false
                var fallbackMessage: String?

                if let sessionError = error as? AgentSessionError {
                    if case .sessionAlreadyActive = sessionError {
                        return
                    }
                    if case .sessionResumeUnsupported = sessionError {
                        shouldAttachHistory = true
                        fallbackMessage = "\(selectedAgentDisplayName) does not support session restore. Starting a new session with local history attached."
                        shouldClearSessionId = false
                        shouldShowFailure = false
                    }
                }

                if let acpError = error as? ClientError,
                   case .agentError = acpError {
                    let message = (acpError.errorDescription ?? "").lowercased()
                    if message.contains("not found") || message.contains("resource_not_found") || message.contains("session not found") {
                        shouldAttachHistory = true
                        fallbackMessage = "Previous session not found on the agent. Starting a new session with local history attached."
                        shouldClearSessionId = true
                        shouldShowFailure = false
                    }
                }

                if shouldAttachHistory,
                   !hasHistoryAttachment(),
                   let compact = compactHistoryMarkdown() {
                    let attachment = ChatAttachment.text(compact)
                    sessionManager.setPendingAttachments(attachments + [attachment], for: sessionId)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        attachments.append(attachment)
                    }
                }

                if let fallbackMessage {
                    agentSession.addSystemMessage(fallbackMessage)
                }
                if shouldShowFailure {
                    logger.error("Failed to resume ACP session \(acpSessionId): \(error.localizedDescription)")
                    agentSession.addSystemMessage("Failed to restore previous session. Starting a new one.")
                }
                if shouldClearSessionId {
                    do {
                        try await ChatSessionPersistence.shared.clearSessionId(for: sessionId, in: viewContext)
                    } catch {
                        logger.error("Failed to clear persisted session ID: \(error.localizedDescription)")
                    }
                }
            }
        }

        do {
            try await agentSession.start(
                agentName: selectedAgent,
                workingDir: worktreePath,
                chatSessionId: sessionId
            )
        } catch {
            if let sessionError = error as? AgentSessionError,
               case .sessionAlreadyActive = sessionError {
                return
            }
            throw error
        }
    }
}
