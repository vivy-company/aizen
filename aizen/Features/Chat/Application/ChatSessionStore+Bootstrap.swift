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
        cancelScheduledAgentSessionActivation()
        prepareAgentSession()
        Task { [weak self] in
            await self?.activatePreparedAgentSessionIfNeeded()
        }
    }

    func prepareAgentSession() {
        guard let sessionId = session.id else { return }

        let worktreePath = worktree.path ?? ""
        prepareWarmState(worktreePath: worktreePath)
        autocompleteHandler.worktreePath = worktreePath

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            bindPreparedSession(existingSession)
            return
        }

        guard !worktreePath.isEmpty else {
            logger.error("Chat session missing worktree path; cannot start agent session.")
            return
        }

        let newSession = ChatAgentSession(agentName: selectedAgent, workingDirectory: worktreePath)
        let worktreeName = worktree.branch ?? "Chat"
        sessionManager.setAgentSession(newSession, for: sessionId, worktreeName: worktreeName)
        bindPreparedSession(newSession)
    }

    func scheduleAgentSessionActivation() {
        cancelScheduledAgentSessionActivation()
        prepareAgentSession()
        let activationDelay = delayedActivationInterval

        delayedActivationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: activationDelay)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            self.delayedActivationTask = nil
            await self.activatePreparedAgentSessionIfNeeded()
        }
    }

    func cancelScheduledAgentSessionActivation() {
        delayedActivationTask?.cancel()
        delayedActivationTask = nil
    }

    private func bindPreparedSession(_ agentSession: ChatAgentSession) {
        if agentSession.messages.isEmpty && !historicalMessages.isEmpty {
            agentSession.messages = historicalMessages
        }
        if agentSession.toolCalls.isEmpty && !historicalToolCalls.isEmpty {
            agentSession.loadPersistedToolCalls(historicalToolCalls)
        }

        currentAgentSession = agentSession
        autocompleteHandler.agentSession = agentSession
        updateDerivedState(from: agentSession)
        bootstrapTimelineState(from: agentSession)
        setupSessionObservers(session: agentSession)
    }

    private func activatePreparedAgentSessionIfNeeded() async {
        delayedActivationTask = nil
        prepareAgentSession()

        guard let sessionId = session.id else { return }
        guard settingUpSessionId != sessionId else { return }

        let worktreePath = worktree.path ?? ""
        guard !worktreePath.isEmpty else {
            logger.error("Chat session missing worktree path; cannot start agent session.")
            return
        }
        guard let agentSession = currentAgentSession else { return }

        scheduleAutocompleteIndexIfNeeded(for: worktreePath)

        settingUpSessionId = sessionId

        defer { settingUpSessionId = nil }

        if !agentSession.isActive {
            do {
                try await startOrResumeSession(agentSession, sessionId: sessionId, worktreePath: worktreePath)
                await sendPendingMessageIfNeeded()
            } catch {
                logger.error("Failed to start session for \(self.selectedAgent): \(error.localizedDescription)")
            }
            return
        }

        await sendPendingMessageIfNeeded()
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

    private func prepareWarmState(worktreePath: String) {
        resetTimelineSyncState()
        loadPendingAttachmentsIfNeeded()

        if !hasLoadedWarmState {
            loadHistoricalMessages()
            hasLoadedWarmState = true
        }

        if indexedAutocompleteWorktreePath != worktreePath {
            hasIndexedAutocompleteWorktree = false
            indexedAutocompleteWorktreePath = worktreePath
        }
    }

    private func scheduleAutocompleteIndexIfNeeded(for worktreePath: String) {
        guard !worktreePath.isEmpty else { return }
        guard !hasIndexedAutocompleteWorktree else { return }

        hasIndexedAutocompleteWorktree = true
        Task { [weak self] in
            guard let self else { return }
            await self.autocompleteHandler.indexWorktree()
        }
    }
}
