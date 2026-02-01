//
//  ChatMessageList.swift
//  aizen
//
//  Simple SwiftUI-based chat message list with auto-scroll behavior.
//

import ACP
import SwiftUI

struct ChatMessageList: View {
    let timelineItems: [TimelineItem]
    let isProcessing: Bool
    let isSessionInitializing: Bool
    let selectedAgent: String
    let currentThought: String?
    let currentIterationId: String?
    let scrollRequest: ChatSessionViewModel.ScrollRequest?
    let turnAnchorMessageId: String?
    let shouldAutoScroll: Bool
    let isResizing: Bool
    let onAppear: () -> Void
    let renderInlineMarkdown: (String) -> AttributedString
    var onToolTap: (ToolCall) -> Void = { _ in }
    var onOpenFileInEditor: (String) -> Void = { _ in }
    var agentSession: AgentSession? = nil
    var onScrollPositionChange: (Bool) -> Void = { _ in }
    var childToolCallsProvider: (String) -> [ToolCall] = { _ in [] }

    // MARK: - State

    @State private var showLoadingView = false
    @State private var loadingStartTime: Date?
    @State private var cachedThoughtText: String?
    @State private var cachedThoughtRendered: AttributedString = AttributedString("")
    @State private var isNearBottom: Bool = true
    @State private var bottomSensorVisible: Bool = true

    private let minimumLoadingDuration: TimeInterval = 0.6
    private let bottomAnchorId = "bottom_anchor"

    // MARK: - Computed

    private var shouldShowLoading: Bool {
        isSessionInitializing && timelineItems.isEmpty
    }

    private var visibleItems: [TimelineItem] {
        timelineItems.filter { item in
            if case .toolCall(let call) = item {
                return call.parentToolCallId == nil
            }
            return true
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            if showLoadingView {
                AgentLoadingView(agentName: selectedAgent)
                    .transition(.opacity)
            } else {
                scrollContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLoadingView)
        .onChange(of: shouldShowLoading) { _, newValue in
            handleLoadingChange(newValue)
        }
        .onChange(of: currentThought) { _, newThought in
            updateCachedThought(newThought)
        }
        .onAppear {
            if shouldShowLoading {
                showLoadingView = true
                loadingStartTime = Date()
            }
            updateCachedThought(currentThought)
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleItems, id: \.stableId) { item in
                        itemView(for: item)
                            .padding(.vertical, itemSpacing(for: item))
                            .id(item.stableId)
                    }

                    if isProcessing {
                        processingIndicator
                            .padding(.horizontal, 20)
                            .id("processing")
                    }

                    // Bottom sensor - detects when we're near bottom
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                        .onAppear {
                            if !bottomSensorVisible {
                                bottomSensorVisible = true
                                isNearBottom = true
                                onScrollPositionChange(true)
                            }
                        }
                        .onDisappear {
                            if bottomSensorVisible {
                                bottomSensorVisible = false
                                isNearBottom = false
                                onScrollPositionChange(false)
                            }
                        }
                }
                .padding(.vertical, 12)
            }
            .onAppear {
                onAppear()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottomIfNeeded(proxy: proxy, animated: false)
                }
            }
            .onChange(of: timelineItems.count) { _, _ in
                if isNearBottom {
                    scrollToBottomIfNeeded(proxy: proxy, animated: false)
                }
            }
            .onChange(of: isProcessing) { _, processing in
                if processing && isNearBottom {
                    scrollToBottomIfNeeded(proxy: proxy, animated: false)
                }
            }
            .onChange(of: currentThought) { _, _ in
                if isNearBottom {
                    scrollToBottomIfNeeded(proxy: proxy, animated: false)
                }
            }
            .onChange(of: scrollRequest?.id) { _, _ in
                if let request = scrollRequest {
                    handleScrollRequest(request, proxy: proxy)
                }
            }
        }
    }

    // MARK: - Item Views

    @ViewBuilder
    private func itemView(for item: TimelineItem) -> some View {
        switch item {
        case .message(let message):
            MessageBubbleView(
                message: message,
                agentName: message.role == .agent ? selectedAgent : nil
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

        case .toolCall(let toolCall):
            if toolCall.parentToolCallId == nil {
                let children = childToolCallsProvider(toolCall.toolCallId)
                ToolCallView(
                    toolCall: toolCall,
                    currentIterationId: currentIterationId,
                    onOpenDetails: { onToolTap($0) },
                    agentSession: agentSession,
                    onOpenInEditor: onOpenFileInEditor,
                    childToolCalls: children
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }

        case .toolCallGroup(let group):
            ToolCallGroupView(
                group: group,
                currentIterationId: currentIterationId,
                agentSession: agentSession,
                onOpenDetails: { onToolTap($0) },
                onOpenInEditor: onOpenFileInEditor,
                childToolCallsProvider: childToolCallsProvider
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

        case .turnSummary(let summary):
            TurnSummaryView(
                summary: summary,
                onOpenInEditor: onOpenFileInEditor
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
    }

    private func itemSpacing(for item: TimelineItem) -> CGFloat {
        switch item {
        case .message:
            return 4  // 8pt total between messages
        case .toolCall, .toolCallGroup:
            return 1  // 2pt total between tool calls (tight)
        case .turnSummary:
            return 4
        }
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)

            if currentThought != nil {
                Text(cachedThoughtRendered)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .modifier(ShimmerEffect(bandSize: 0.38, duration: 2.2, baseOpacity: 0.08, highlightOpacity: 1.0))
            } else {
                Text("chat.agent.thinking", bundle: .main)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .modifier(ShimmerEffect(bandSize: 0.38, duration: 2.2, baseOpacity: 0.08, highlightOpacity: 1.0))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Scroll Helpers

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
        // State will be updated by onAppear of bottom sensor
    }

    private func handleScrollRequest(_ request: ChatSessionViewModel.ScrollRequest, proxy: ScrollViewProxy) {
        switch request.target {
        case .bottom:
            // Immediately activate auto-follow mode
            isNearBottom = true
            bottomSensorVisible = true
            onScrollPositionChange(true)
            scrollToBottomIfNeeded(proxy: proxy, animated: request.animated)
        case .item(let id, let anchor):
            if request.animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: anchor)
                }
            } else {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    // MARK: - Loading Helpers

    private func handleLoadingChange(_ shouldShow: Bool) {
        if shouldShow {
            showLoadingView = true
            loadingStartTime = Date()
        } else {
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

    private func updateCachedThought(_ thought: String?) {
        guard thought != cachedThoughtText else { return }
        cachedThoughtText = thought
        if let thought {
            cachedThoughtRendered = renderInlineMarkdown(thought)
        } else {
            cachedThoughtRendered = AttributedString("")
        }
    }
}
