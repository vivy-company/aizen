//
//  ChatSessionStore+SessionObservers.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import ACP
import Combine
import Foundation
import SwiftUI

@MainActor
extension ChatSessionStore {
    func setupSessionObservers(session: ChatAgentSession) {
        if currentAgentSession === session,
           observedSessionId == self.session.id,
           !cancellables.isEmpty {
            isProcessing = session.isStreaming
            updateDerivedState(from: session)
            return
        }

        cancellables.removeAll()
        observedSessionId = self.session.id

        isProcessing = session.isStreaming
        updateDerivedState(from: session)
        skipNextMessagesEmission = true
        skipNextToolCallsEmission = true

        session.$messages
            .removeDuplicates(by: Self.hasEquivalentMessageEnvelope)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMessages in
                guard let self else { return }
                if self.skipNextMessagesEmission {
                    self.skipNextMessagesEmission = false
                    return
                }
                self.syncMessages(newMessages)
                self.timelineStore.suppressNextAutoScroll = false
            }
            .store(in: &cancellables)

        session.$toolCallsById
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let session = self.currentAgentSession else { return }
                if self.skipNextToolCallsEmission {
                    self.skipNextToolCallsEmission = false
                    return
                }
                self.syncToolCalls(session.toolCalls)
            }
            .store(in: &cancellables)

        session.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if !isActive {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.isProcessing = false
                    }
                }
            }
            .store(in: &cancellables)

        session.$needsAuthentication
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsAuth in
                self?.needsAuth = needsAuth
            }
            .store(in: &cancellables)

        session.$needsAgentSetup
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsSetup in
                self?.needsSetup = needsSetup
            }
            .store(in: &cancellables)

        session.$needsUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsUpdate in
                self?.needsUpdate = needsUpdate
            }
            .store(in: &cancellables)

        session.$versionInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] versionInfo in
                self?.versionInfo = versionInfo
            }
            .store(in: &cancellables)

        session.$agentPlan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in
                self?.currentAgentPlan = plan
            }
            .store(in: &cancellables)

        session.$availableModes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modes in
                self?.availableModes = modes
            }
            .store(in: &cancellables)

        session.$availableModels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] models in
                self?.availableModels = models
            }
            .store(in: &cancellables)

        session.$availableConfigOptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                self?.availableConfigOptions = options
            }
            .store(in: &cancellables)

        session.$currentModeId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modeId in
                self?.currentModeId = modeId
            }
            .store(in: &cancellables)

        session.$currentModelId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modelId in
                self?.currentModelId = modelId
            }
            .store(in: &cancellables)

        session.$sessionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.sessionState = state
                self?.timelineStore.isSessionInitializing = state.isInitializing
            }
            .store(in: &cancellables)

        session.$isResumingSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isResuming in
                self?.isResumingSession = isResuming
            }
            .store(in: &cancellables)

        session.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStreaming in
                guard let self else { return }
                self.isProcessing = isStreaming
                self.timelineStore.isStreaming = isStreaming

                if let path = self.worktree.path, !path.isEmpty {
                    if isStreaming && !self.gitPauseApplied {
                        self.gitPauseApplied = true
                        NotificationCenter.default.post(
                            name: .agentStreamingDidStart,
                            object: nil,
                            userInfo: ["worktreePath": path]
                        )
                        WorktreeRuntimeCoordinator.shared
                            .runtime(for: path)
                            .setGitRefreshSuspended(true)
                    } else if !isStreaming && self.gitPauseApplied {
                        self.gitPauseApplied = false
                        NotificationCenter.default.post(
                            name: .agentStreamingDidStop,
                            object: nil,
                            userInfo: ["worktreePath": path]
                        )
                        WorktreeRuntimeCoordinator.shared
                            .runtime(for: path)
                            .setGitRefreshSuspended(false)
                    }
                }

                let streamingEnded = self.wasStreaming && !isStreaming
                self.wasStreaming = isStreaming

                if streamingEnded {
                    if let lastAgent = session.messages.last(where: { $0.role == .agent }),
                       lastAgent.isComplete == false {
                        session.markLastMessageComplete()
                    }
                }
            }
            .store(in: &cancellables)

        session.permissionHandler.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                self?.showingPermissionAlert = showing
            }
            .store(in: &cancellables)

        session.permissionHandler.$permissionRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                self?.currentPermissionRequest = request
            }
            .store(in: &cancellables)
    }
}
