//
//  ChatSessionViewModel+Timeline.swift
//  aizen
//
//  Timeline invalidation and scroll operations for chat sessions
//

import ACP
import Foundation

extension ChatSessionViewModel {
    struct ScrollRequest: Equatable {
        enum Target: Equatable {
            case bottom
        }

        let id: UUID
        let target: Target
        let animated: Bool
        let force: Bool
    }

    func rebuildTimeline() {
        timelineRenderEpoch &+= 1
    }

    func rebuildTimelineWithGrouping(isStreaming: Bool) {
        _ = isStreaming
        timelineRenderEpoch &+= 1
    }

    func syncMessages(_ newMessages: [MessageItem]) {
        previousMessageIds = Set(newMessages.map(\.id))
        timelineRenderEpoch &+= 1
    }

    func syncToolCalls(_ newToolCalls: [ToolCall]) {
        previousToolCallIds = Set(newToolCalls.map(\.id))
        timelineRenderEpoch &+= 1
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
