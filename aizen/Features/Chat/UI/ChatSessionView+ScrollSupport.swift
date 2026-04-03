import ACP
import CoreData
import SwiftUI
import VVChatTimeline

extension ChatSessionView {
    var shouldShowScrollToBottom: Bool {
        (!chatTimelineState.isLiveTail || chatTimelineState.hasUnreadNewContent)
            && (!viewModel.messages.isEmpty || !viewModel.toolCalls.isEmpty)
    }

    func scrollToBottom() {
        viewModel.scrollToBottom()
    }

    @ViewBuilder
    var scrollToBottomButton: some View {
        Button(action: scrollToBottom) {
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
