//
//  ChatMessageList.swift
//  aizen
//
//  Message list view with timeline items
//

import SwiftUI

struct ChatMessageList: View {
    let timelineItems: [TimelineItem]
    let isProcessing: Bool
    let selectedAgent: String
    let currentThought: String?
    let onScrollProxyReady: (ScrollViewProxy) -> Void
    let onAppear: () -> Void
    let renderInlineMarkdown: (String) -> AttributedString
    var onToolTap: (ToolCall) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(timelineItems, id: \.id) { item in
                        switch item {
                        case .message(let message):
                            MessageBubbleView(message: message, agentName: message.role == .agent ? selectedAgent : nil)
                                .id(message.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        case .toolCall(let toolCall):
                            ToolCallView(toolCall: toolCall) { tapped in
                                onToolTap(tapped)
                            }
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }

                    if isProcessing {
                        processingIndicator
                            .id("processing")
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
            }
            .onAppear {
                onScrollProxyReady(proxy)
                onAppear()
            }
        }
    }

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .controlSize(.small)

            if let thought = currentThought {
                Text(renderInlineMarkdown(thought))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .modifier(ShimmerEffect())
                    .transition(.opacity)
            } else {
                Text("chat.agent.thinking", bundle: .main)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .modifier(ShimmerEffect())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
