//
//  ChatSessionStore+Observation.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import Combine
import ACP
import Foundation
import SwiftUI

@MainActor
extension ChatSessionStore {
    func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .cycleModeShortcut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cycleModeForward()
            }
            .store(in: &notificationCancellables)

        NotificationCenter.default.publisher(for: .interruptAgentShortcut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cancelCurrentPrompt()
            }
            .store(in: &notificationCancellables)
    }

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
                self.suppressNextAutoScroll = false
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
                self.performStreamingRebuildIfReady()
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
                self?.hasModes = !modes.isEmpty
            }
            .store(in: &cancellables)

        session.$currentModeId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modeId in
                self?.currentModeId = modeId
            }
            .store(in: &cancellables)

        session.$sessionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.sessionState = state
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
                    let currentToolCallIds = Set(session.toolCalls.map(\.id))
                    self.pendingStreamingRebuild = true
                    self.pendingStreamingRebuildRequiresToolCallSync = currentToolCallIds != self.previousToolCallIds
                    self.scheduleStreamingRebuild()
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

    static func hasEquivalentMessageEnvelope(_ lhs: [MessageItem], _ rhs: [MessageItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        guard let left = lhs.last, let right = rhs.last else {
            return lhs.isEmpty && rhs.isEmpty
        }

        let leftTail = left.content.suffix(64)
        let rightTail = right.content.suffix(64)
        return left.id == right.id
            && left.isComplete == right.isComplete
            && left.content.count == right.content.count
            && leftTail == rightTail
            && left.contentBlocks.count == right.contentBlocks.count
    }

    func resetTimelineSyncState() {
        cancelPendingAutoScroll()
        scrollRequest = nil

        streamingRebuildTask?.cancel()
        streamingRebuildTask = nil
        pendingStreamingRebuild = false
        pendingStreamingRebuildRequiresToolCallSync = false

        skipNextMessagesEmission = false
        skipNextToolCallsEmission = false
    }

    func bootstrapTimelineState(from session: ChatAgentSession) {
        previousMessageIds = Set(messages.map(\.id))
        previousToolCallIds = Set(session.toolCalls.map(\.id))

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rebuildTimelineWithGrouping(isStreaming: session.isStreaming)
        }
    }

    func scheduleStreamingRebuild() {
        guard streamingRebuildTask == nil else { return }
        streamingRebuildTask = Task { @MainActor in
            defer { streamingRebuildTask = nil }
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled {
                return
            }
            performStreamingRebuildIfReady()
        }
    }

    func performStreamingRebuildIfReady() {
        guard pendingStreamingRebuild else { return }
        guard !(currentAgentSession?.isStreaming ?? false) else { return }
        if pendingStreamingRebuildRequiresToolCallSync {
            let currentToolCallIds = Set(currentAgentSession?.toolCalls.map(\.id) ?? [])
            if currentToolCallIds != previousToolCallIds {
                return
            }
        }
        rebuildTimelineWithGrouping(isStreaming: false)
        previousMessageIds = Set(messages.map(\.id))
        if let session = currentAgentSession {
            previousToolCallIds = Set(session.toolCalls.map(\.id))
        }
        pendingStreamingRebuild = false
        pendingStreamingRebuildRequiresToolCallSync = false
    }
}
