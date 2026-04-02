import ACP
import SwiftUI
import VVChatTimeline

struct ChatTimelineRenderKey: Equatable {
    let timelineRenderEpoch: UInt64
    let isSessionInitializing: Bool
    let pendingPlanRequestIdentity: String
    let selectedAgent: String
    let scrollRequestId: UUID?
}

struct ChatTimelineContainer: View, Equatable {
    let key: ChatTimelineRenderKey
    let messages: [MessageItem]
    let toolCalls: [ToolCall]
    let isStreaming: Bool
    let isSessionInitializing: Bool
    let pendingPlanRequest: RequestPermissionRequest?
    let worktreePath: String?
    let selectedAgent: String
    let scrollRequest: ChatSessionStore.ScrollRequest?
    let isAutoScrollEnabled: () -> Bool
    let onAppear: () -> Void
    let onTimelineStateChange: (VVChatTimelineState) -> Void

    static func == (lhs: ChatTimelineContainer, rhs: ChatTimelineContainer) -> Bool {
        lhs.key == rhs.key
    }

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
