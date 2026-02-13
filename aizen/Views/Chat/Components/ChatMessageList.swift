//
//  ChatMessageList.swift
//  aizen
//
//  Simple SwiftUI-based chat message list with auto-scroll behavior.
//

import AppKit
import ACP
import SwiftUI

struct ChatMessageList: View {
    let timelineItems: [TimelineItem]
    let isProcessing: Bool
    let isSessionInitializing: Bool
    let pendingPlanRequest: RequestPermissionRequest?
    let selectedAgent: String
    let currentThought: String?
    let currentIterationId: String?
    let scrollRequest: ChatSessionViewModel.ScrollRequest?
    let turnAnchorMessageId: String?
    var isAutoScrollEnabled: () -> Bool = { true }
    let isResizing: Bool
    let onAppear: () -> Void
    let renderInlineMarkdown: (String) -> AttributedString
    var worktreePath: String? = nil
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
    @State private var loadedTimelineItemCount: Int = 0
    @State private var isShowingFullHistory: Bool = false
    @State private var lastReportedBottomVisibility: Bool?

    private let minimumLoadingDuration: TimeInterval = 0.6
    private let bottomAnchorId = "bottom_anchor"
    private let bottomSensorHeight: CGFloat = 24
    private let initialTimelineWindowSize = 140
    private let timelineWindowStep = 120
    private let messageHorizontalPadding: CGFloat = 20
    private let systemAndThinkingHorizontalPadding: CGFloat = 28

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

    private var effectiveLoadedTimelineItemCount: Int {
        if isShowingFullHistory {
            return visibleItems.count
        }
        return min(max(loadedTimelineItemCount, 0), visibleItems.count)
    }

    private var timelineWindowStartIndex: Int {
        max(0, visibleItems.count - effectiveLoadedTimelineItemCount)
    }

    private var windowedVisibleItems: [TimelineItem] {
        Array(visibleItems.dropFirst(timelineWindowStartIndex))
    }

    private var hiddenOlderItemCount: Int {
        timelineWindowStartIndex
    }

    private var planRequestIdentity: String {
        guard let request = pendingPlanRequest else { return "none" }
        let optionIds = (request.options ?? []).map(\.optionId).joined(separator: "|")
        let toolId = request.toolCall?.toolCallId ?? "none"
        return "req-\(toolId)-\(optionIds)-\(request.message ?? "")"
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
            scrollViewWithAnchoring {
                VStack(spacing: 0) {
                    if hiddenOlderItemCount > 0 {
                        loadOlderControl(proxy: proxy)
                    }

                    ForEach(windowedVisibleItems, id: \.stableId) { item in
                        itemView(for: item)
                            .padding(.vertical, itemSpacing(for: item))
                            .id(item.stableId)
                    }

                    if let request = pendingPlanRequest {
                        PlanRequestInlineView(request: request)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                            .id("plan-request-\(planRequestIdentity)")
                    }

                    if isProcessing {
                        processingIndicator
                            .padding(.horizontal, systemAndThinkingHorizontalPadding)
                            .id("processing")
                    }

                    bottomVisibilitySensor
                }
                .padding(.vertical, 12)
            }
            .onAppear {
                onAppear()
                bootstrapTimelineWindowIfNeeded(totalCount: visibleItems.count)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottomIfNeeded(proxy: proxy, animated: false)
                }
            }
            .onChange(of: visibleItems.count) { oldCount, newCount in
                updateTimelineWindowOnCountChange(oldCount: oldCount, newCount: newCount)
            }
            .onChange(of: isProcessing) { _, _ in
                if isAutoScrollEnabled() {
                    scheduleScrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: planRequestIdentity) { _, _ in
                if isAutoScrollEnabled() {
                    scheduleScrollToBottom(proxy: proxy, animated: true)
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
            let horizontalPadding = message.role == .system
                ? systemAndThinkingHorizontalPadding
                : messageHorizontalPadding
            MessageBubbleView(
                message: message,
                agentName: message.role == .agent ? selectedAgent : nil,
                markdownBasePath: worktreePath,
                onOpenFileInEditor: onOpenFileInEditor
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)

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

    @ViewBuilder
    private var bottomVisibilitySensor: some View {
        Color.clear
            .frame(height: bottomSensorHeight)
            .id(bottomAnchorId)
            .background(
                ScrollBottomObserver(
                    threshold: bottomSensorHeight,
                    onChange: reportBottomVisibility
                )
                .frame(width: 0, height: 0)
            )
    }

    @ViewBuilder
    private func scrollViewWithAnchoring<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 15.0, *) {
            ScrollView {
                content()
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            ScrollView {
                content()
            }
        }
    }

    // MARK: - Scroll Helpers

    private func scheduleScrollToBottom(
        proxy: ScrollViewProxy,
        animated: Bool,
        respectAutoScroll: Bool = true
    ) {
        Task { @MainActor in
            await Task.yield()
            if respectAutoScroll && !isAutoScrollEnabled() {
                return
            }
            scrollToBottomIfNeeded(proxy: proxy, animated: animated)
        }
    }

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
    }

    private func handleScrollRequest(_ request: ChatSessionViewModel.ScrollRequest, proxy: ScrollViewProxy) {
        switch request.target {
        case .bottom:
            if request.force {
                reportBottomVisibility(true)
                scheduleScrollToBottom(proxy: proxy, animated: request.animated, respectAutoScroll: false)
                Task { @MainActor in
                    await Task.yield()
                    scrollToBottomIfNeeded(proxy: proxy, animated: false)
                }
                return
            }

            guard isAutoScrollEnabled() else {
                return
            }
            scheduleScrollToBottom(proxy: proxy, animated: request.animated, respectAutoScroll: true)
        case .item(let id, let anchor):
            if let requiredCount = requiredLoadedCount(for: id),
               loadedTimelineItemCount < requiredCount {
                loadedTimelineItemCount = requiredCount
                if requiredCount >= visibleItems.count {
                    isShowingFullHistory = true
                }
                Task { @MainActor in
                    await Task.yield()
                    scrollToItem(id: id, anchor: anchor, proxy: proxy, animated: request.animated)
                }
                return
            }
            scrollToItem(id: id, anchor: anchor, proxy: proxy, animated: request.animated)
        }
    }

    private func reportBottomVisibility(_ isVisible: Bool) {
        guard lastReportedBottomVisibility != isVisible else { return }
        lastReportedBottomVisibility = isVisible
        DispatchQueue.main.async {
            onScrollPositionChange(isVisible)
        }
    }

    private func scrollToItem(id: String, anchor: UnitPoint, proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }

    @ViewBuilder
    private func loadOlderControl(proxy: ScrollViewProxy) -> some View {
        let remaining = hiddenOlderItemCount
        Button {
            loadOlderItems(proxy: proxy)
        } label: {
            Text("Load more (\(remaining) remaining)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func loadOlderItems(proxy: ScrollViewProxy) {
        guard hiddenOlderItemCount > 0 else { return }
        let anchorId = windowedVisibleItems.first?.stableId
        let increment = min(timelineWindowStep, hiddenOlderItemCount)
        loadedTimelineItemCount += increment
        if loadedTimelineItemCount >= visibleItems.count {
            isShowingFullHistory = true
        }
        Task { @MainActor in
            await Task.yield()
            if let anchorId {
                proxy.scrollTo(anchorId, anchor: .top)
            }
        }
    }

    private func requiredLoadedCount(for itemId: String) -> Int? {
        guard let index = visibleItems.firstIndex(where: { $0.stableId == itemId }) else { return nil }
        return visibleItems.count - index
    }

    private func bootstrapTimelineWindowIfNeeded(totalCount: Int) {
        guard loadedTimelineItemCount == 0 else { return }
        loadedTimelineItemCount = min(totalCount, initialTimelineWindowSize)
        isShowingFullHistory = totalCount <= initialTimelineWindowSize
    }

    private func updateTimelineWindowOnCountChange(oldCount: Int, newCount: Int) {
        if newCount == 0 {
            loadedTimelineItemCount = 0
            isShowingFullHistory = false
            return
        }

        if loadedTimelineItemCount == 0 {
            loadedTimelineItemCount = min(newCount, initialTimelineWindowSize)
            isShowingFullHistory = newCount <= initialTimelineWindowSize
            return
        }

        if isShowingFullHistory {
            loadedTimelineItemCount = newCount
            return
        }

        // Keep a bounded recent-history window for better scroll performance.
        if loadedTimelineItemCount < initialTimelineWindowSize {
            loadedTimelineItemCount = min(newCount, initialTimelineWindowSize)
            isShowingFullHistory = newCount <= initialTimelineWindowSize
            return
        }

        // Preserve currently visible history while user is scrolled up.
        // Without this, incoming items shift the window forward and hide content being read.
        if newCount > oldCount, !isAutoScrollEnabled() {
            loadedTimelineItemCount = min(newCount, loadedTimelineItemCount + (newCount - oldCount))
            if loadedTimelineItemCount >= newCount {
                isShowingFullHistory = true
            }
        }

        if loadedTimelineItemCount > newCount {
            loadedTimelineItemCount = newCount
        }

        if oldCount <= initialTimelineWindowSize,
           newCount > initialTimelineWindowSize,
           loadedTimelineItemCount < initialTimelineWindowSize {
            loadedTimelineItemCount = initialTimelineWindowSize
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

private struct ScrollBottomObserver: NSViewRepresentable {
    let threshold: CGFloat
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(threshold: threshold, onChange: onChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.scheduleAttach(to: view, forceEvaluate: true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.threshold = threshold
        context.coordinator.onChange = onChange
        context.coordinator.scheduleAttach(to: nsView, forceEvaluate: false)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var threshold: CGFloat
        var onChange: (Bool) -> Void

        private weak var scrollView: NSScrollView?
        private weak var documentView: NSView?
        private var boundsObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var lastState: Bool?
        private var pendingAttachWorkItem: DispatchWorkItem?

        init(threshold: CGFloat, onChange: @escaping (Bool) -> Void) {
            self.threshold = threshold
            self.onChange = onChange
        }

        func scheduleAttach(to view: NSView, forceEvaluate: Bool) {
            if resolveScrollView(from: view) != nil {
                pendingAttachWorkItem?.cancel()
                pendingAttachWorkItem = nil
                let hadAttachedScrollView = scrollView != nil
                attach(to: view)
                if forceEvaluate || !hadAttachedScrollView {
                    evaluateNow()
                }
                return
            }

            if pendingAttachWorkItem != nil {
                return
            }

            let workItem = DispatchWorkItem { [weak self, weak view] in
                guard let self, let view else { return }
                self.pendingAttachWorkItem = nil
                let hadAttachedScrollView = self.scrollView != nil
                self.attach(to: view)
                if forceEvaluate || !hadAttachedScrollView {
                    self.evaluateNow()
                }
            }
            pendingAttachWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        func attach(to view: NSView) {
            guard let resolvedScrollView = resolveScrollView(from: view) else { return }
            guard resolvedScrollView !== scrollView else { return }

            detach()
            scrollView = resolvedScrollView
            observe(scrollView: resolvedScrollView)
            evaluateNow()
        }

        func evaluateNow() {
            guard let scrollView else { return }
            refreshDocumentObservation(for: scrollView)
            guard let documentView = scrollView.documentView else {
                emit(true)
                return
            }

            let visibleRect = documentView.convert(scrollView.contentView.bounds, from: scrollView.contentView)
            let distanceToBottom: CGFloat
            if documentView.isFlipped {
                distanceToBottom = max(documentView.bounds.maxY - visibleRect.maxY, 0)
            } else {
                distanceToBottom = max(visibleRect.minY - documentView.bounds.minY, 0)
            }
            emit(distanceToBottom <= threshold + 0.5)
        }

        func detach() {
            pendingAttachWorkItem?.cancel()
            pendingAttachWorkItem = nil
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            boundsObserver = nil
            frameObserver = nil
            scrollView = nil
            documentView = nil
            lastState = nil
        }

        private func observe(scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateNow()
            }

            if let documentView = scrollView.documentView {
                self.documentView = documentView
                documentView.postsFrameChangedNotifications = true
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.evaluateNow()
                }
            }
        }

        private func refreshDocumentObservation(for scrollView: NSScrollView) {
            guard scrollView.documentView !== documentView else { return }

            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            frameObserver = nil
            documentView = scrollView.documentView

            if let documentView {
                documentView.postsFrameChangedNotifications = true
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.evaluateNow()
                }
            }
        }

        private func emit(_ isNearBottom: Bool) {
            guard lastState != isNearBottom else { return }
            lastState = isNearBottom
            onChange(isNearBottom)
        }

        private func resolveScrollView(from view: NSView) -> NSScrollView? {
            if let enclosing = view.enclosingScrollView {
                return enclosing
            }

            var node: NSView? = view
            while let current = node {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                node = current.superview
            }
            return nil
        }
    }
}
