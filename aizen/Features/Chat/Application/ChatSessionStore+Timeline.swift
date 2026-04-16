//
//  ChatSessionStore+Timeline.swift
//  aizen
//
//  Timeline invalidation and scroll operations for chat sessions
//

import ACP
import Foundation

extension ChatSessionStore {
    func syncMessages(_ newMessages: [MessageItem]) {
        timelineStore.syncMessages(newMessages)
    }

    func syncToolCalls(_ newToolCalls: [ToolCall]) {
        timelineStore.syncToolCalls(newToolCalls)
    }

    func syncTimeline(messages newMessages: [MessageItem], toolCalls newToolCalls: [ToolCall]) {
        timelineStore.syncTimeline(messages: newMessages, toolCalls: newToolCalls)
    }

    // MARK: - Scrolling

    func scrollToBottom() {
        timelineStore.scrollToBottom()
    }

    /// Deferred scroll that avoids "ScrollViewProxy may not be accessed during view updates" crash
    func scrollToBottomDeferred() {
        timelineStore.scrollToBottomDeferred()
    }

    func cancelPendingAutoScroll() {
        timelineStore.cancelPendingAutoScroll()
    }
}
