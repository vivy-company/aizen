//
//  ChatSessionStore+Timeline.swift
//  aizen
//
//  Timeline invalidation and scroll operations for chat sessions
//

import ACP
import Foundation

extension ChatSessionStore {
    struct ScrollRequest: Equatable {
        enum Target: Equatable {
            case bottom
        }

        let id: UUID
        let target: Target
        let animated: Bool
        let force: Bool
    }

    func syncMessages(_ newMessages: [MessageItem]) {
        messages = filteredTimelineMessages(from: newMessages)
    }

    func syncToolCalls(_ newToolCalls: [ToolCall]) {
        toolCalls = newToolCalls
    }

    func syncTimeline(messages newMessages: [MessageItem], toolCalls newToolCalls: [ToolCall]) {
        syncMessages(newMessages)
        syncToolCalls(newToolCalls)
    }

    private func filteredTimelineMessages(from source: [MessageItem]) -> [MessageItem] {
        source.filter { message in
            guard message.role == .agent else { return true }
            return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Scrolling

    func scrollToBottom() {
        userScrolledUp = false
        requestScrollToBottom(force: true, animated: true)
    }

    /// Deferred scroll that avoids "ScrollViewProxy may not be accessed during view updates" crash
    func scrollToBottomDeferred() {
        scheduleAutoScrollToBottom()
    }

    private func requestScrollToBottom(force: Bool, animated: Bool) {
        scrollRequest = ScrollRequest(id: UUID(), target: .bottom, animated: animated, force: force)
    }

    private func scheduleAutoScrollToBottom() {
        guard !userScrolledUp else { return }
        guard !suppressNextAutoScroll else { return }
        guard autoScrollTask == nil else { return }

        autoScrollTask = Task { @MainActor in
            defer { autoScrollTask = nil }
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled || userScrolledUp || suppressNextAutoScroll {
                return
            }
            scrollRequest = ScrollRequest(id: UUID(), target: .bottom, animated: false, force: false)
        }
    }

    func cancelPendingAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
}
