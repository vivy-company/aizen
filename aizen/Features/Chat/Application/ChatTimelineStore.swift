//
//  ChatTimelineStore.swift
//  aizen
//
//  High-frequency timeline state for chat sessions.
//

import ACP
import Combine
import Foundation

@MainActor
final class ChatTimelineStore: ObservableObject {
    struct ScrollRequest: Equatable {
        enum Target: Equatable {
            case bottom
        }

        let id: UUID
        let target: Target
        let animated: Bool
        let force: Bool
    }

    @Published var messages: [MessageItem] = []
    @Published var toolCalls: [ToolCall] = []
    @Published var isStreaming = false
    @Published var isSessionInitializing = false
    @Published var scrollRequest: ScrollRequest?
    @Published var isNearBottom = true

    /// Tracks user intent: true when the user has actively scrolled away from bottom.
    var userScrolledUp = false

    private var autoScrollTask: Task<Void, Never>?
    private var pendingNearBottomState: Bool?
    private var nearBottomStateTask: Task<Void, Never>?
    var suppressNextAutoScroll = false

    deinit {
        autoScrollTask?.cancel()
        nearBottomStateTask?.cancel()
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

    func resetSyncState() {
        cancelPendingAutoScroll()
        scrollRequest = nil
        suppressNextAutoScroll = false
        pendingNearBottomState = nil
        userScrolledUp = false
        isNearBottom = true
    }

    func bootstrap(from session: ChatAgentSession) {
        syncTimeline(messages: session.messages, toolCalls: session.toolCalls)
        isStreaming = session.isStreaming
        isSessionInitializing = session.sessionState.isInitializing
    }

    func enqueueScrollPositionChange(_ nextIsNearBottom: Bool, isLayoutResizing: Bool) {
        guard !isLayoutResizing else { return }

        if pendingNearBottomState == nextIsNearBottom, nearBottomStateTask != nil {
            return
        }
        pendingNearBottomState = nextIsNearBottom

        guard nearBottomStateTask == nil else { return }
        nearBottomStateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.nearBottomStateTask = nil }

            guard let nextState = self.pendingNearBottomState else { return }
            self.pendingNearBottomState = nil
            self.applyScrollPositionChange(nextState)
        }
    }

    func scrollToBottom() {
        userScrolledUp = false
        requestScrollToBottom(force: true, animated: true)
    }

    /// Deferred scroll that avoids "ScrollViewProxy may not be accessed during view updates" crash.
    func scrollToBottomDeferred() {
        scheduleAutoScrollToBottom()
    }

    func cancelPendingAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func filteredTimelineMessages(from source: [MessageItem]) -> [MessageItem] {
        source.filter { message in
            guard message.role == .agent else { return true }
            return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func applyScrollPositionChange(_ nextIsNearBottom: Bool) {
        if isNearBottom != nextIsNearBottom {
            isNearBottom = nextIsNearBottom
        }

        if !nextIsNearBottom && !userScrolledUp {
            userScrolledUp = true
        }
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
}
