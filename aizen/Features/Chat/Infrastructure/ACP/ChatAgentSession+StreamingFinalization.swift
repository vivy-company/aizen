//
//  ChatAgentSession+StreamingFinalization.swift
//  aizen
//
//  Streaming buffering and finalization helpers.
//

import ACP
import Combine
import CoreData
import Foundation
import UniformTypeIdentifiers

@MainActor
extension ChatAgentSession {
    // MARK: - Streaming Finalization

    func resetFinalizeState() {
        finalizeMessageTask?.cancel()
        finalizeMessageTask = nil
        lastAgentChunkAt = nil
    }

    func appendThoughtChunk(_ text: String) {
        thoughtBuffer += text
        scheduleThoughtFlush()
    }

    func clearThoughtBuffer() {
        thoughtBuffer = ""
        thoughtFlushTask?.cancel()
        thoughtFlushTask = nil
        if currentThought != nil {
            currentThought = nil
        }
    }

    func scheduleThoughtFlush() {
        guard thoughtFlushTask == nil else { return }
        thoughtFlushTask = Task { @MainActor in
            defer { thoughtFlushTask = nil }
            try? await Task.sleep(for: .seconds(Self.thoughtUpdateInterval))
            let nextThought: String? = thoughtBuffer.isEmpty ? nil : thoughtBuffer
            if currentThought != nextThought {
                currentThought = nextThought
            }
        }
    }

    func appendAgentMessageChunk(text: String, contentBlocks: [ContentBlock]) {
        pendingAgentText += text
        if !contentBlocks.isEmpty {
            pendingAgentBlocks.append(contentsOf: contentBlocks)
        }
        scheduleAgentMessageFlush()
    }

    func flushAgentMessageBuffer() {
        guard !pendingAgentText.isEmpty || !pendingAgentBlocks.isEmpty else { return }
        agentMessageFlushTask?.cancel()
        agentMessageFlushTask = nil

        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            let lastAgentMessage = messages[lastIndex]
            let newContent = lastAgentMessage.content + pendingAgentText
            var newBlocks = lastAgentMessage.contentBlocks
            if !pendingAgentBlocks.isEmpty {
                newBlocks.append(contentsOf: pendingAgentBlocks)
            }
            let updatedMessage = MessageItem(
                id: lastAgentMessage.id,
                role: .agent,
                content: newContent,
                timestamp: lastAgentMessage.timestamp,
                toolCalls: lastAgentMessage.toolCalls,
                contentBlocks: newBlocks,
                isComplete: false,
                startTime: lastAgentMessage.startTime,
                executionTime: lastAgentMessage.executionTime,
                requestId: lastAgentMessage.requestId
            )
            var updatedMessages = messages
            updatedMessages[lastIndex] = updatedMessage
            messages = updatedMessages
        }

        pendingAgentText = ""
        pendingAgentBlocks = []
    }

    func clearAgentMessageBuffer() {
        pendingAgentText = ""
        pendingAgentBlocks = []
        agentMessageFlushTask?.cancel()
        agentMessageFlushTask = nil
    }

    func scheduleAgentMessageFlush() {
        if Self.agentMessageFlushInterval == 0 {
            flushAgentMessageBuffer()
            return
        }

        guard agentMessageFlushTask == nil else { return }
        agentMessageFlushTask = Task { @MainActor in
            defer { agentMessageFlushTask = nil }
            try? await Task.sleep(for: .seconds(Self.agentMessageFlushInterval))
            flushAgentMessageBuffer()
        }
    }

    func recordAgentChunk() {
        lastAgentChunkAt = Date()
    }

    func scheduleFinalizeLastMessage() {
        finalizeMessageTask?.cancel()
        finalizeMessageTask = Task { @MainActor in
            while true {
                let delay: TimeInterval
                if let last = lastAgentChunkAt {
                    let elapsed = Date().timeIntervalSince(last)
                    delay = max(0.0, Self.finalizeIdleDelay - elapsed)
                } else {
                    delay = Self.finalizeIdleDelay
                }

                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }

                guard !Task.isCancelled else { return }

                if let last = lastAgentChunkAt,
                   Date().timeIntervalSince(last) < Self.finalizeIdleDelay {
                    continue
                }

                markLastMessageComplete()
                return
            }
        }
    }
}
