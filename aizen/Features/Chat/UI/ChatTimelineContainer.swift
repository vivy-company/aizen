import ACP
import SwiftUI
import VVChatTimeline

struct ChatTimelinePane: View {
    @ObservedObject var timelineStore: ChatTimelineStore
    let pendingPlanRequest: RequestPermissionRequest?
    let worktreePath: String?
    let selectedAgent: String
    let onAppear: () -> Void
    let isLayoutResizing: Bool

    @State private var chatTimelineState = VVChatTimelineState()

    var body: some View {
        ZStack(alignment: .bottom) {
            ChatTimelineContainer(
                messages: timelineStore.messages,
                toolCalls: timelineStore.toolCalls,
                isStreaming: timelineStore.isStreaming,
                isSessionInitializing: timelineStore.isSessionInitializing,
                pendingPlanRequest: pendingPlanRequest,
                worktreePath: worktreePath,
                selectedAgent: selectedAgent,
                scrollRequest: timelineStore.scrollRequest,
                isAutoScrollEnabled: { !timelineStore.userScrolledUp },
                onAppear: onAppear,
                onTimelineStateChange: { state in
                    chatTimelineState = state
                    timelineStore.enqueueScrollPositionChange(
                        state.isLiveTail,
                        isLayoutResizing: isLayoutResizing
                    )
                }
            )
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            scrollToBottomButton
                .padding(.bottom, 16)
                .opacity(shouldShowScrollToBottom ? 1 : 0)
                .allowsHitTesting(shouldShowScrollToBottom)
                .accessibilityHidden(!shouldShowScrollToBottom)
        }
    }

    private var shouldShowScrollToBottom: Bool {
        (!chatTimelineState.isLiveTail || chatTimelineState.hasUnreadNewContent)
            && (!timelineStore.messages.isEmpty || !timelineStore.toolCalls.isEmpty)
    }

    @ViewBuilder
    private var scrollToBottomButton: some View {
        Button(action: timelineStore.scrollToBottom) {
            if #available(macOS 26.0, *) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .glassEffect(.regular, in: Circle())
                    .contentShape(Circle())
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                    )
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
    }
}

struct ChatTimelineContainer: View {
    let messages: [MessageItem]
    let toolCalls: [ToolCall]
    let isStreaming: Bool
    let isSessionInitializing: Bool
    let pendingPlanRequest: RequestPermissionRequest?
    let worktreePath: String?
    let selectedAgent: String
    let scrollRequest: ChatTimelineStore.ScrollRequest?
    let isAutoScrollEnabled: () -> Bool
    let onAppear: () -> Void
    let onTimelineStateChange: (VVChatTimelineState) -> Void

    var body: some View {
        ChatMessageList(
            messages: messages,
            toolCalls: toolCalls,
            isStreaming: isStreaming,
            isSessionInitializing: isSessionInitializing,
            pendingPlanRequest: pendingPlanRequest,
            worktreePath: worktreePath,
            selectedAgent: selectedAgent,
            scrollRequest: scrollRequest,
            isAutoScrollEnabled: isAutoScrollEnabled,
            onAppear: onAppear,
            onTimelineStateChange: onTimelineStateChange
        )
    }
}
