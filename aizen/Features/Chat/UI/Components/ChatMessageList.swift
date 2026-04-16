//
//  ChatMessageList.swift
//  aizen
//
//  VVDevKit-backed chat timeline list.
//

import ACP
import AppKit
import SwiftUI
import VVCode
import VVChatTimeline
import VVMarkdown
import VVMetalPrimitives

struct ChatMessageList: View {
    let messages: [MessageItem]
    let toolCalls: [ToolCall]
    let isStreaming: Bool
    let isSessionInitializing: Bool
    let pendingPlanRequest: RequestPermissionRequest?
    let worktreePath: String?
    let selectedAgent: String
    let scrollRequest: ChatTimelineStore.ScrollRequest?
    var isAutoScrollEnabled: () -> Bool = { true }
    let onAppear: () -> Void
    var onTimelineStateChange: (VVChatTimelineState) -> Void = { _ in }

    @AppStorage(AppearanceSettings.markdownFontFamilyKey) var markdownFontFamily = AppearanceSettings.defaultMarkdownFontFamily
    @AppStorage(AppearanceSettings.markdownFontSizeKey) var markdownFontSize = AppearanceSettings.defaultMarkdownFontSize
    @AppStorage(AppearanceSettings.markdownParagraphSpacingKey) var markdownParagraphSpacing = AppearanceSettings.defaultMarkdownParagraphSpacing
    @AppStorage(AppearanceSettings.markdownHeadingSpacingKey) var markdownHeadingSpacing = AppearanceSettings.defaultMarkdownHeadingSpacing
    @AppStorage(AppearanceSettings.markdownContentPaddingKey) var markdownContentPadding = AppearanceSettings.defaultMarkdownContentPadding
    @AppStorage(AppearanceSettings.themeNameKey) var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) var terminalUsePerAppearanceTheme = false
    @Environment(\.colorScheme) var colorScheme

    @State var controller = VVChatTimelineController(style: .init(), renderWidth: 0)
    @State var appliedEntries: [VVChatTimelineEntry] = []
    @State var lastBuildMetadata = TimelineBuildMetadata()
    @State var lastReportedTimelineState: VVChatTimelineState?
    @State var copiedUserMessageID: String?
    @State var copiedUserMessageState: CopyFooterState = .idle
    @State var hoveredCopyUserMessageID: String?
    @State var copyIndicatorResetTask: Task<Void, Never>?
    @State var expandedToolGroupIDs: Set<String> = []
    @State var suppressNextTimelineSignatureSync = false

    private var shouldShowLoading: Bool {
        isSessionInitializing && messages.isEmpty && toolCalls.isEmpty
    }

    var topLevelToolCalls: [ToolCall] {
        toolCalls.filter { $0.parentToolCallId == nil }
    }

    private var timelineSignature: Int {
        var hasher = Hasher()
        hasher.combine(messages.count)
        for message in messages {
            hasher.combine(messageRevisionToken(message))
        }
        hasher.combine(topLevelToolCalls.count)
        for toolCall in topLevelToolCalls {
            hasher.combine(toolCallRevisionToken(toolCall))
        }
        hasher.combine(planRequestIdentity)
        hasher.combine(isStreaming)
        hasher.combine(copiedUserMessageID)
        hasher.combine(copyFooterStateToken(for: copiedUserMessageID ?? ""))
        for groupID in expandedToolGroupIDs.sorted() {
            hasher.combine(groupID)
        }
        return hasher.finalize()
    }

    var planRequestIdentity: String {
        guard let request = pendingPlanRequest else { return "none" }
        let optionIds = request.options.map(\.optionId).joined(separator: "|")
        let toolId = request.toolCall.toolCallId
        let title = request.toolCall.title ?? ""
        return "req-\(toolId)-\(optionIds)-\(title)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if shouldShowLoading {
                AgentLoadingView(agentName: selectedAgent)
            } else {
                ChatTimelineHost(
                    controller: controller,
                    scrollRequest: scrollRequest,
                    onStateChange: reportTimelineStateIfNeeded,
                    onUserMessageCopyAction: handleUserMessageCopyAction,
                    onUserMessageCopyHoverChange: handleUserMessageCopyHoverChange,
                    onEntryActivate: handleEntryActivate,
                    onLinkActivate: handleTimelineLinkActivate
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            onAppear()
            controller.updateStyle(timelineStyle)
            syncTimeline(scrollToBottom: true)
            reportTimelineStateIfNeeded(controller.state)
        }
        .task(id: timelineSignature) {
            if suppressNextTimelineSignatureSync {
                suppressNextTimelineSignatureSync = false
                return
            }
            syncTimeline(scrollToBottom: isAutoScrollEnabled())
        }
        .task(id: timelineStyleSignature) {
            controller.updateStyle(timelineStyle)
            syncTimeline(scrollToBottom: false)
        }
        .onDisappear {
            copyIndicatorResetTask?.cancel()
        }
    }

    func syncTimeline(scrollToBottom: Bool) {
        let build = buildTimeline()
        lastBuildMetadata = build.metadata
        apply(entries: build.entries, scrollToBottom: scrollToBottom)
    }
}

enum CopyFooterState {
    case idle
    case transition
    case confirmed
}
