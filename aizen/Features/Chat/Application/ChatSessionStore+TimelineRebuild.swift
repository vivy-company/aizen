//
//  ChatSessionStore+TimelineRebuild.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import ACP
import Foundation
import SwiftUI

@MainActor
extension ChatSessionStore {
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
