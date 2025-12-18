//
//  ChatMessageList.swift
//  aizen
//
//  Message list view with timeline items
//

import SwiftUI

// MARK: - Preference Keys for Scroll Detection

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatMessageList: View {
    let timelineItems: [TimelineItem]
    let isProcessing: Bool
    let isSessionInitializing: Bool
    let selectedAgent: String
    let currentThought: String?
    let currentIterationId: String?
    let onScrollProxyReady: (ScrollViewProxy) -> Void
    let onAppear: () -> Void
    let renderInlineMarkdown: (String) -> AttributedString
    var onToolTap: (ToolCall) -> Void = { _ in }
    var onOpenFileInEditor: (String) -> Void = { _ in }
    var agentSession: AgentSession? = nil
    var onScrollPositionChange: (Bool) -> Void = { _ in }
    var childToolCallsProvider: (String) -> [ToolCall] = { _ in [] }

    // Minimum display time for loading view to prevent flashing
    @State private var showLoadingView = false
    @State private var loadingStartTime: Date?
    private let minimumLoadingDuration: TimeInterval = 0.6

    private var shouldShowLoading: Bool {
        isSessionInitializing && timelineItems.isEmpty
    }

    var body: some View {
        ZStack {
            if showLoadingView {
                AgentLoadingView(agentName: selectedAgent)
                    .transition(.opacity)
            } else {
                messageListContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showLoadingView)
        .onChange(of: shouldShowLoading) { newValue in
            if newValue {
                // Start showing loading
                showLoadingView = true
                loadingStartTime = Date()
            } else {
                // Ensure minimum display time before hiding
                guard let startTime = loadingStartTime else {
                    showLoadingView = false
                    return
                }
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = minimumLoadingDuration - elapsed
                if remaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                        showLoadingView = false
                    }
                } else {
                    showLoadingView = false
                }
            }
        }
        .onAppear {
            // Initialize loading state on appear
            if shouldShowLoading {
                showLoadingView = true
                loadingStartTime = Date()
            }
        }
    }

    private var messageListContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(timelineItems, id: \.id) { item in
                        switch item {
                        case .message(let message):
                            MessageBubbleView(message: message, agentName: message.role == .agent ? selectedAgent : nil)
                                .id(item.id)  // Use dynamic id to force re-render when content changes
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        case .toolCall(let toolCall):
                            // Skip child tool calls (rendered inside parent Task)
                            if toolCall.parentToolCallId != nil {
                                EmptyView()
                            } else {
                                let children = childToolCallsProvider(toolCall.toolCallId)
                                ToolCallView(
                                    toolCall: toolCall,
                                    currentIterationId: currentIterationId,
                                    onOpenDetails: { tapped in onToolTap(tapped) },
                                    agentSession: agentSession,
                                    onOpenInEditor: onOpenFileInEditor,
                                    childToolCalls: children
                                )
                                .id(item.id)  // Use dynamic id to force re-render when status changes
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        case .toolCallGroup(let group):
                            ToolCallGroupView(
                                group: group,
                                currentIterationId: currentIterationId,
                                agentSession: agentSession,
                                onOpenInEditor: onOpenFileInEditor,
                                childToolCallsProvider: childToolCallsProvider
                            )
                            .id(item.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }

                    if isProcessing {
                        processingIndicator
                            .id("processing")
                            .transition(.opacity)
                    }

                    // Bottom anchor for scroll position detection
                    Color.clear
                        .frame(height: 1)
                        .id("bottom_anchor")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear
                            .preference(key: ScrollContentHeightKey.self, value: contentGeometry.size.height)
                            .preference(key: ScrollOffsetKey.self, value: contentGeometry.frame(in: .named("scroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .background(
                GeometryReader { scrollGeometry in
                    Color.clear
                        .preference(key: ScrollViewHeightKey.self, value: scrollGeometry.size.height)
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                updateScrollState(offset: offset)
            }
            .onPreferenceChange(ScrollContentHeightKey.self) { content in
                updateScrollState(content: content)
            }
            .onPreferenceChange(ScrollViewHeightKey.self) { viewport in
                updateScrollState(viewport: viewport)
            }
            .onAppear {
                onScrollProxyReady(proxy)
                onAppear()
            }
        }
    }

    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var lastReportedNearBottom: Bool = true

    private func updateScrollState(offset: CGFloat? = nil, content: CGFloat? = nil, viewport: CGFloat? = nil) {
        if let offset = offset { scrollOffset = offset }
        if let content = content { contentHeight = content }
        if let viewport = viewport { scrollViewHeight = viewport }

        // Calculate if we're near the bottom
        // scrollOffset is negative when scrolled down (content moves up)
        // When at bottom: -scrollOffset + viewportHeight >= contentHeight
        let distanceFromBottom = contentHeight + scrollOffset - scrollViewHeight
        let isNearBottom = distanceFromBottom <= 50 || contentHeight <= scrollViewHeight

        if isNearBottom != lastReportedNearBottom {
            lastReportedNearBottom = isNearBottom
            onScrollPositionChange(isNearBottom)
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
