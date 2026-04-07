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
    let scrollRequest: ChatSessionStore.ScrollRequest?
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
        let optionIds = (request.options ?? []).map(\.optionId).joined(separator: "|")
        let toolId = request.toolCall?.toolCallId ?? "none"
        return "req-\(toolId)-\(optionIds)-\(request.message ?? "")"
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

    

    func entryRevision(_ entry: VVChatTimelineEntry) -> Int {
        switch entry {
        case .message(let message):
            return message.revision
        case .custom(let custom):
            return custom.revision
        }
    }

    func diffLineDelta(oldText: String?, newText: String) -> (added: Int, removed: Int) {
        diffLineDelta(
            oldLines: diffTextLines(oldText),
            newLines: diffTextLines(newText)
        )
    }

    private func diffTextLines(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func diffLineDelta(oldLines: [String], newLines: [String]) -> (added: Int, removed: Int) {
        if oldLines.isEmpty && newLines.isEmpty {
            return (0, 0)
        }
        if oldLines.isEmpty {
            return (newLines.count, 0)
        }
        if newLines.isEmpty {
            return (0, oldLines.count)
        }

        let lcs = longestCommonSubsequence(oldLines, newLines)
        var oldIndex = 0
        var newIndex = 0
        var lcsIndex = 0
        var added = 0
        var removed = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if lcsIndex < lcs.count,
               oldIndex < oldLines.count,
               newIndex < newLines.count,
               oldLines[oldIndex] == lcs[lcsIndex],
               newLines[newIndex] == lcs[lcsIndex] {
                oldIndex += 1
                newIndex += 1
                lcsIndex += 1
            } else if oldIndex < oldLines.count,
                      lcsIndex >= lcs.count || oldLines[oldIndex] != lcs[lcsIndex] {
                removed += 1
                oldIndex += 1
            } else if newIndex < newLines.count {
                added += 1
                newIndex += 1
            }
        }

        return (added, removed)
    }

    func primaryPath(for toolCall: ToolCall) -> String? {
        if let path = toolCall.locations?.first?.path {
            return path
        }

        for content in toolCall.content {
            if case .diff(let diff) = content {
                return diff.path
            }
        }

        if toolCall.title.contains("/") {
            return toolCall.title
        }

        return nil
    }

    func isToolGroupEntryID(_ entryID: String) -> Bool {
        lastBuildMetadata.groupEntryIDs.contains(entryID)
    }

    func destinationPath(from url: URL) -> String? {
        if url.scheme?.lowercased() == "aizen-file" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let rawPath = components.queryItems?.first(where: { $0.name == "path" })?.value,
                  !rawPath.isEmpty else {
                return nil
            }
            return resolveSummaryFilePath(rawPath)
        }

        if url.isFileURL {
            return url.standardizedFileURL.path
        }

        return nil
    }

    func inlineDiffPreviewDocument(for diff: ToolCallDiff) -> String {
        diffDocument(for: diff, contextLines: 2, maxOutputLines: 16)
    }

    func revisionKey(_ value: String) -> Int {
        let hashed = value.hashValue
        if hashed == Int.min {
            return Int.max
        }
        return abs(hashed)
    }
}

enum CopyFooterState {
    case idle
    case transition
    case confirmed
}
