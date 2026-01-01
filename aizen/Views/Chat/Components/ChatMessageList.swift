//
//  ChatMessageList.swift
//  aizen
//
//  Message list view with timeline items
//

import AppKit
import SwiftUI

// MARK: - Scroll Observation

private struct ScrollViewObserver: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, CGFloat) -> Void
    let scrollToBottomRequest: UUID?
    let animated: Bool
    let force: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll

        // Check if we need to scroll
        let currentRequest = scrollToBottomRequest
        let lastRequest = context.coordinator.lastScrollRequest

        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView)

            // Only scroll if request changed
            if currentRequest != lastRequest {
                context.coordinator.lastScrollRequest = currentRequest
                if currentRequest != nil {
                    context.coordinator.scrollToBottom(animated: animated)
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDownObservers()
    }

    final class Coordinator: NSObject {
        var onScroll: (CGFloat, CGFloat, CGFloat) -> Void
        var lastScrollRequest: UUID?
        private(set) weak var scrollView: NSScrollView?
        private weak var documentView: NSView?
        private var boundsObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?

        init(onScroll: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
            self.onScroll = onScroll
        }

        deinit {
            tearDownObservers()
        }

        func attach(to view: NSView) {
            guard let foundScrollView = findScrollView(from: view) else { return }

            if foundScrollView !== scrollView {
                tearDownObservers()
                scrollView = foundScrollView
                observe(scrollView: foundScrollView)
                return
            }

            if let foundDocumentView = foundScrollView.documentView,
                foundDocumentView !== documentView
            {
                observeDocumentView(foundDocumentView)
            }
        }

        func scrollToBottom(animated: Bool) {
            guard let scrollView = scrollView,
                let documentView = scrollView.documentView
            else { return }

            let contentHeight = documentView.bounds.height
            let viewportHeight = scrollView.contentView.bounds.height
            let maxY = max(0, contentHeight - viewportHeight)

            let targetPoint: NSPoint
            if documentView.isFlipped {
                targetPoint = NSPoint(x: 0, y: maxY)
            } else {
                targetPoint = NSPoint(x: 0, y: 0)
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(targetPoint)
                }
            } else {
                scrollView.contentView.setBoundsOrigin(targetPoint)
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func findScrollView(from view: NSView) -> NSScrollView? {
            if let scrollView = view.enclosingScrollView {
                return scrollView
            }

            var currentSuperview = view.superview
            while let current = currentSuperview {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                currentSuperview = current.superview
            }

            return nil
        }

        private func observe(scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.notifyScrollPosition()
            }

            if let documentView = scrollView.documentView {
                observeDocumentView(documentView)
            }

            notifyScrollPosition()
        }

        private func observeDocumentView(_ documentView: NSView) {
            if documentView === self.documentView {
                return
            }

            if let frameObserver = frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
                self.frameObserver = nil
            }

            self.documentView = documentView
            documentView.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self] _ in
                self?.notifyScrollPosition()
            }
        }

        private func notifyScrollPosition() {
            guard let scrollView = scrollView else { return }
            let contentHeight = scrollView.documentView?.bounds.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            let rawOffset = scrollView.contentView.bounds.origin.y
            let offsetFromTop: CGFloat
            if let documentView = scrollView.documentView, !documentView.isFlipped {
                let maxOffset = max(0, contentHeight - viewportHeight)
                offsetFromTop = maxOffset - rawOffset
            } else {
                offsetFromTop = rawOffset
            }
            onScroll(-offsetFromTop, contentHeight, viewportHeight)
        }

        func tearDownObservers() {
            if let boundsObserver = boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver = frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            boundsObserver = nil
            frameObserver = nil
            documentView = nil
        }
    }
}

struct ChatMessageList: View {
    let timelineItems: [TimelineItem]
    let isProcessing: Bool
    let isSessionInitializing: Bool
    let selectedAgent: String
    let currentThought: String?
    let currentIterationId: String?
    let scrollRequest: ChatSessionViewModel.ScrollRequest?
    let shouldAutoScroll: Bool
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
    @State private var allowAnimations = false
    @State private var cachedThoughtText: String? = nil
    @State private var cachedThoughtRendered: AttributedString = AttributedString("")

    private var shouldShowLoading: Bool {
        isSessionInitializing && timelineItems.isEmpty
    }

    private var enableScrollObserver: Bool {
        true
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
        .animation(allowAnimations ? .easeInOut(duration: 0.25) : nil, value: showLoadingView)
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
            updateCachedThought(currentThought)
        }
        .task {
            // Enable animations after a brief delay to avoid modifying state during view update
            if !allowAnimations {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                allowAnimations = true
            }
        }
        .onChange(of: currentThought) { newThought in
            updateCachedThought(newThought)
        }
    }

    private var messageListContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(timelineItems, id: \.stableId) { item in
                        switch item {
                        case .message(let message):
                            MessageBubbleView(
                                message: message,
                                agentName: message.role == .agent ? selectedAgent : nil
                            )
                            .id(message.id)
                            .transition(
                                message.isComplete
                                    ? .opacity.combined(with: .scale(scale: 0.95)) : .identity)
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
                                .id(toolCall.id)
                                .transition(
                                    toolCall.status == .pending
                                        ? .opacity.combined(with: .move(edge: .leading)) : .identity
                                )
                            }
                        case .toolCallGroup(let group):
                            ToolCallGroupView(
                                group: group,
                                currentIterationId: currentIterationId,
                                agentSession: agentSession,
                                onOpenDetails: { tapped in onToolTap(tapped) },
                                onOpenInEditor: onOpenFileInEditor,
                                childToolCallsProvider: childToolCallsProvider
                            )
                            .id(group.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                        case .turnSummary(let summary):
                            TurnSummaryView(
                                summary: summary,
                                onOpenInEditor: onOpenFileInEditor
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(summary.id)
                            .transition(.opacity)
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
                .transaction { transaction in
                    // Disable animations during initial load or when processing
                    // to prevent empty screen issues during rapid updates
                    if !allowAnimations || isProcessing {
                        transaction.disablesAnimations = true
                    }
                }
                .background {
                    if enableScrollObserver {
                        ScrollViewObserver(
                            onScroll: { offset, contentHeight, viewportHeight in
                                updateScrollState(
                                    offset: offset, content: contentHeight, viewport: viewportHeight)
                            },
                            scrollToBottomRequest: scrollToBottomRequestId,
                            animated: scrollRequest?.animated ?? true,
                            force: scrollRequest?.force ?? false
                        )
                    }
                }
            }
            .onChange(of: scrollRequest) { request in
                guard let request = request else { return }
                guard case .item(let targetId, let anchor) = request.target else { return }
                DispatchQueue.main.async {
                    if request.animated {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(targetId, anchor: anchor)
                        }
                    } else {
                        proxy.scrollTo(targetId, anchor: anchor)
                    }
                }
            }
            .onAppear {
                onAppear()
            }
        }
    }

    /// Only trigger scroll if force is true or auto-scroll is enabled
    private var shouldTriggerScroll: Bool {
        guard let request = scrollRequest else { return false }
        guard case .bottom = request.target else { return false }
        return request.force || shouldAutoScroll
    }

    private var scrollToBottomRequestId: UUID? {
        guard let request = scrollRequest else { return nil }
        guard case .bottom = request.target else { return nil }
        guard shouldTriggerScroll else { return nil }
        return request.id
    }

    @State private var lastReportedNearBottom: Bool? = nil

    private func updateScrollState(
        offset: CGFloat, content: CGFloat, viewport: CGFloat
    ) {
        // Calculate if we're near the bottom
        // scrollOffset is negative when scrolled down (content moves up)
        // When at bottom: -scrollOffset + viewportHeight >= contentHeight
        let distanceFromBottom = content + offset - viewport
        let isNearBottom = distanceFromBottom <= 50 || content <= viewport

        // Only report when state changes
        guard isNearBottom != lastReportedNearBottom else { return }
        let nextValue = isNearBottom
        let callback = onScrollPositionChange

        // Use Task to defer state modification to next run loop iteration
        // This avoids "Modifying state during view update" warnings
        Task { @MainActor in
            guard nextValue != lastReportedNearBottom else { return }
            lastReportedNearBottom = nextValue
            callback(nextValue)
        }
    }

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
                    .transition(.opacity)
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
