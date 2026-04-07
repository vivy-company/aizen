//
//  ChatAgentSession+StreamingNotifications.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation

@MainActor
extension ChatAgentSession {
    func handleAgentMessageChunk(_ block: ContentBlock) {
        clearThoughtBuffer()
        currentThought = nil
        let (text, blockContent) = textAndContent(from: block)
        if shouldSkipResumedAgentChunk(text: text, hasContentBlocks: !blockContent.isEmpty) {
            return
        }
        if text.isEmpty && blockContent.isEmpty {
            return
        }
        recordAgentChunk()

        // Find the last agent message (not just last message)
        // This prevents system messages (like mode changes) from splitting the stream
        let lastAgentMessage = messages.last { $0.role == .agent }

        if let lastAgentMessage = lastAgentMessage,
           !lastAgentMessage.isComplete {
            // Append to the active agent message immediately so the timeline can stream each chunk.
            appendAgentMessageChunk(text: text, contentBlocks: blockContent)
        } else {
            AgentUsageStore.shared.recordAgentMessage(agentId: agentName)
            clearAgentMessageBuffer()
            addAgentMessage(text, contentBlocks: blockContent, isComplete: false, startTime: Date())
        }
    }

    func handleAgentThoughtChunk(_ block: ContentBlock) {
        let (text, _) = textAndContent(from: block)
        if text.isEmpty {
            return
        }
        appendThoughtChunk(text)
    }
}
