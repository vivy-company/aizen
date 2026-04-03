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

    private var planRequestIdentity: String {
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

    var customEntryMessageMapper: VVChatTimelineController.CustomEntryMessageMapper {
        { custom in
            let decoded = decodeCustomPayload(from: custom.payload)
            let content = decoded?.body ?? String(data: custom.payload, encoding: .utf8) ?? "[\(custom.kind)]"
            let role: VVChatMessageRole
            let presentation: VVChatMessagePresentation?
            let showsAgentLaneIcon = decoded?.showsAgentLaneIcon == true
            let headerTitle = decoded?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let headerIconURL = toolHeaderIconURL(for: decoded?.toolKind)
            var messageContent = content
            var customContent: VVChatCustomContent?

            let statusTintColor = toolGroupStatusNSColor(statusRawValue: decoded?.status)
            let vvBadges: [VVHeaderBadge]? = decoded?.badges?.map { badge in
                VVHeaderBadge(text: badge.text, color: SIMD4<Float>(badge.r, badge.g, badge.b, badge.a))
            }

            switch custom.kind {
            case "toolCall":
                role = .assistant
                messageContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : content
                let statusTintedIconURL = toolHeaderIconURL(for: decoded?.toolKind, tintColor: statusTintColor)
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: statusTintedIconURL ?? headerIconURL,
                    leadingLaneWidth: agentLaneWidth,
                    leadingIconURL: showsAgentLaneIcon ? agentLaneIconURL : nil,
                    leadingIconSize: showsAgentLaneIcon ? agentLaneIconSize : nil,
                    leadingIconSpacing: showsAgentLaneIcon ? agentLaneIconSpacing : nil,
                    showsTimestamp: false,
                    contentFontScale: 0.70,
                    textOpacityMultiplier: dimmedMetaOpacity,
                    headerBadges: vvBadges
                )
            case "toolCallDetail":
                role = .assistant
                messageContent = ""
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: toolHeaderIconURL(for: decoded?.toolKind, tintColor: statusTintColor) ?? headerIconURL,
                    leadingLaneWidth: agentLaneWidth,
                    showsTimestamp: false,
                    contentFontScale: 0.72,
                    textOpacityMultiplier: dimmedMetaOpacity * 0.93,
                    headerBadges: vvBadges
                )
            case "toolCallInlineDiff":
                role = .assistant
                messageContent = ""
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: false,
                    leadingLaneWidth: agentLaneWidth,
                    showsTimestamp: false,
                    contentFontScale: 0.82,
                    textOpacityMultiplier: 0.97
                )
                customContent = .inlineDiff(.init(unifiedDiff: content))
            case "toolCallGroup":
                role = .assistant
                messageContent = ""
                let isGroupExpanded = expandedToolGroupIDs.contains(custom.id)
                let chevronSymbol = isGroupExpanded ? "chevron.down" : "chevron.right"
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: symbolIconURL("square.stack.3d.up", fallbackID: "tool-group-\(decoded?.status ?? "default")", tintColor: statusTintColor),
                    headerTrailingIconURL: symbolIconURL(chevronSymbol, fallbackID: "chevron-\(isGroupExpanded ? "down" : "right")", tintColor: headerIconTintColor),
                    leadingLaneWidth: agentLaneWidth,
                    leadingIconURL: showsAgentLaneIcon ? agentLaneIconURL : nil,
                    leadingIconSize: showsAgentLaneIcon ? agentLaneIconSize : nil,
                    leadingIconSpacing: showsAgentLaneIcon ? agentLaneIconSpacing : nil,
                    showsTimestamp: false,
                    contentFontScale: 0.74,
                    textOpacityMultiplier: dimmedMetaOpacity
                )
            case "turnSummary":
                role = .assistant
                messageContent = ""
                if let summaryCard = decoded?.summaryCard {
                    customContent = .summaryCard(makeSummaryCard(from: summaryCard))
                }
                presentation = VVChatMessagePresentation(
                    bubbleStyle: turnSummaryBubbleStyle,
                    showsHeader: false,
                    leadingLaneWidth: agentLaneWidth,
                    leadingIconURL: showsAgentLaneIcon ? agentLaneIconURL : nil,
                    leadingIconSize: showsAgentLaneIcon ? agentLaneIconSize : nil,
                    leadingIconSpacing: showsAgentLaneIcon ? agentLaneIconSpacing : nil,
                    showsTimestamp: false,
                    contentFontScale: 0.86,
                    textOpacityMultiplier: colorScheme == .dark ? 0.86 : 0.90
                )
            case "turnSummaryFile":
                role = .assistant
                presentation = VVChatMessagePresentation(
                    bubbleStyle: turnSummaryFileBubbleStyle,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: symbolIconURL(
                        "doc.text",
                        fallbackID: "turn-summary-file",
                        tintColor: headerIconTintColor,
                        pointSize: 13
                    ),
                    leadingLaneWidth: agentLaneWidth,
                    leadingIconURL: nil,
                    leadingIconSize: nil,
                    leadingIconSpacing: nil,
                    showsTimestamp: false,
                    contentFontScale: 0.77,
                    textOpacityMultiplier: dimmedMetaOpacity
                )
            default:
                role = .system
                presentation = nil
            }

            return VVChatMessage(
                id: custom.id,
                role: role,
                state: .final,
                content: messageContent,
                revision: custom.revision,
                timestamp: custom.timestamp,
                presentation: presentation,
                customContent: customContent
            )
        }
    }

    private func toolHeaderIconURL(for kindRawValue: String?) -> String? {
        symbolIconURL(
            toolHeaderSymbol(for: kindRawValue),
            fallbackID: "tool-\(kindRawValue ?? "unknown")",
            tintColor: headerIconTintColor
        )
    }

    private func toolHeaderIconURL(for kindRawValue: String?, tintColor: NSColor) -> String? {
        let symbol = toolHeaderSymbol(for: kindRawValue)
        return symbolIconURL(
            symbol,
            fallbackID: "tool-\(kindRawValue ?? "unknown")-\(tintColor.hashValue)",
            tintColor: tintColor
        )
    }

    func symbolIconURL(_ symbolName: String, fallbackID: String? = nil, tintColor: NSColor? = nil, pointSize: CGFloat? = nil) -> String? {
        let resolvedTintColor = tintColor ?? headerIconTintColor
        return ChatTimelineHeaderIconStore.urlString(
            for: .sfSymbol(symbolName),
            fallbackAgentId: fallbackID ?? "symbol-\(symbolName)",
            tintColor: resolvedTintColor,
            targetPointSize: pointSize ?? 14
        )
    }

    private func toolHeaderSymbol(for kindRawValue: String?) -> String {
        switch kindRawValue {
        case "read":
            return "doc.text.magnifyingglass"
        case "edit":
            return "pencil"
        case "delete":
            return "trash"
        case "move":
            return "arrow.left.and.right.square"
        case "task":
            return "checklist"
        case "execute":
            return "terminal"
        case "search":
            return "magnifyingglass"
        case "think":
            return "brain.head.profile"
        case "fetch":
            return "globe"
        case "plan":
            return "list.bullet.clipboard"
        case "switchMode":
            return "arrow.triangle.swap"
        default:
            return "wrench.and.screwdriver"
        }
    }

    private var turnSummaryBubbleStyle: VVChatBubbleStyle {
        let theme = activeTerminalVVTheme
        let background = theme?.backgroundColor ?? GhosttyThemeParser.loadBackgroundColor(named: effectiveTerminalThemeName)
        let divider = GhosttyThemeParser.loadDividerColor(named: effectiveTerminalThemeName)
        return VVChatBubbleStyle(
            isEnabled: true,
            color: simdColor(from: background).withOpacity(colorScheme == .dark ? 0.92 : 0.98),
            borderColor: simdColor(from: divider).withOpacity(colorScheme == .dark ? 0.34 : 0.18),
            borderWidth: 0.8,
            cornerRadius: 14,
            insets: .init(top: 10, left: 14, bottom: 10, right: 14),
            maxWidth: 920,
            alignment: .leading
        )
    }

    private var turnSummaryFileBubbleStyle: VVChatBubbleStyle {
        VVChatBubbleStyle(
            isEnabled: true,
            color: colorScheme == .dark ? .rgba(0.12, 0.14, 0.17, 0.52) : .rgba(0.98, 0.985, 0.992, 0.95),
            borderColor: colorScheme == .dark ? .rgba(0.52, 0.56, 0.62, 0.14) : .rgba(0.56, 0.60, 0.68, 0.12),
            borderWidth: 0.7,
            cornerRadius: 12,
            insets: .init(top: 8, left: 12, bottom: 8, right: 12),
            maxWidth: 740,
            alignment: .leading
        )
    }

    private struct TimelineBuildResult {
        let entries: [VVChatTimelineEntry]
        let metadata: TimelineBuildMetadata
    }

    struct TimelineBuildMetadata {
        var messagesByID: [String: MessageItem] = [:]
        var toolCallsByEntryID: [String: ToolCall] = [:]
        var groupEntryIDs: Set<String> = []
    }

    enum TimelineSourceItem {
        case message(MessageItem)
        case toolCall(ToolCall)
        case toolCallGroup(ToolCallGroup)
        case turnSummary(TurnSummary)
    }

    struct FileChangeSummary: Identifiable {
        let path: String
        let isNew: Bool
        var linesAdded: Int
        var linesRemoved: Int

        var id: String { path }
    }

    struct TurnSummary: Identifiable {
        let id: String
        let timestamp: Date
        let duration: TimeInterval
        let toolCallCount: Int
        let fileChanges: [FileChangeSummary]

        var entryID: String { "summary-\(id)" }

        var formattedDuration: String {
            if duration < 1 {
                return "<1s"
            } else if duration < 60 {
                return "\(Int(duration))s"
            } else {
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                return "\(minutes)m \(seconds)s"
            }
        }
    }

    struct ToolCallGroup: Identifiable {
        let id: String
        let toolCalls: [ToolCall]
        let timestamp: Date

        var entryID: String { "group-\(id)" }

        init(toolCalls: [ToolCall]) {
            let sorted = toolCalls.sorted { $0.timestamp < $1.timestamp }
            self.id = sorted.first?.id ?? UUID().uuidString
            self.toolCalls = sorted
            self.timestamp = sorted.first?.timestamp ?? .distantPast
        }

        var hasFailed: Bool {
            toolCalls.contains { $0.status == .failed }
        }

        var isInProgress: Bool {
            toolCalls.contains { $0.status == .inProgress || $0.status == .pending }
        }

        var formattedDuration: String? {
            guard let start = toolCalls.map(\.timestamp).min() else { return nil }
            guard let end = toolCalls
                .filter({ $0.status == .completed || $0.status == .failed })
                .map(\.timestamp)
                .max() else { return nil }

            let duration = end.timeIntervalSince(start)
            if duration < 1 {
                return "<1s"
            } else if duration < 60 {
                return "\(Int(duration))s"
            } else {
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                return "\(minutes)m \(seconds)s"
            }
        }
    }

    private func buildTimeline() -> TimelineBuildResult {
        let sourceItems = assembleTimelineSourceItems()
        var metadata = TimelineBuildMetadata()
        var entries: [VVChatTimelineEntry] = []
        entries.reserveCapacity(sourceItems.count + (pendingPlanRequest == nil ? 0 : 1))
        var hasRenderedAgentMessageInTurn = false

        for item in sourceItems {
            switch item {
            case .message(let message):
                metadata.messagesByID[message.id] = message
                let startsAssistantLane = message.role == .agent && !hasRenderedAgentMessageInTurn
                let built = makeEntries(from: item, startsAssistantLane: startsAssistantLane)
                if !built.isEmpty {
                    entries.append(contentsOf: built)
                    if message.role == .agent {
                        hasRenderedAgentMessageInTurn = true
                    } else {
                        hasRenderedAgentMessageInTurn = false
                    }
                } else if message.role != .agent {
                    hasRenderedAgentMessageInTurn = false
                }
            case .toolCall(let toolCall):
                metadata.toolCallsByEntryID[toolCall.id] = toolCall
                let built = makeEntries(from: item, startsAssistantLane: false)
                if !built.isEmpty {
                    entries.append(contentsOf: built)
                }
            case .toolCallGroup(let group):
                metadata.groupEntryIDs.insert(group.entryID)
                for call in group.toolCalls {
                    metadata.toolCallsByEntryID["\(group.entryID)::call::\(call.id)"] = call
                    metadata.toolCallsByEntryID[call.id] = call
                }
                let built = makeEntries(from: item, startsAssistantLane: false)
                if !built.isEmpty {
                    entries.append(contentsOf: built)
                }
            case .turnSummary:
                let built = makeEntries(from: item, startsAssistantLane: false)
                if !built.isEmpty {
                    entries.append(contentsOf: built)
                }
            }
        }

        if let request = pendingPlanRequest {
            let markdown = planRequestMarkdown(request)
            entries.append(
                .message(
                    VVChatMessage(
                        id: "plan-request-\(planRequestIdentity)",
                        role: .system,
                        state: .final,
                        content: markdown,
                        revision: revisionKey(markdown + planRequestIdentity),
                        timestamp: nil
                    )
                )
            )
        }

        return TimelineBuildResult(entries: entries, metadata: metadata)
    }

    func makeEntries(from item: TimelineSourceItem, startsAssistantLane: Bool) -> [VVChatTimelineEntry] {
        switch item {
        case .message(let message):
            let content = messageMarkdown(message)
            if message.role == .agent && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }

            let messageRevisionSeed = "\(message.id)|\(message.isComplete)|\(message.content)|\(message.contentBlocks.count)|normalized:\(content)"

            if message.role == .system {
                let compact = content.trimmingCharacters(in: .whitespacesAndNewlines)
                return [.message(VVChatMessage(
                    id: message.id,
                    role: .system,
                    state: .final,
                    content: compact,
                    revision: revisionKey(messageRevisionSeed + compact),
                    timestamp: nil,
                    presentation: VVChatMessagePresentation(
                        showsHeader: false,
                        showsTimestamp: false,
                        contentFontScale: 0.78,
                        textOpacityMultiplier: colorScheme == .dark ? 0.5 : 0.58
                    )
                ))]
            }

            return [.message(VVChatMessage(
                id: message.id,
                role: mapRole(message.role),
                state: message.role == .agent && !message.isComplete ? .draft : .final,
                content: content,
                revision: revisionKey(messageRevisionSeed + "|" + presentationRevisionToken(for: message, startsAssistantLane: startsAssistantLane)),
                timestamp: message.timestamp,
                presentation: messagePresentation(for: message, startsAssistantLane: startsAssistantLane)
            ))]

        case .toolCall(let toolCall):
            let title = toolCallHeaderTitle(toolCall)
            let markdown = toolCallMarkdown(toolCall)
            let encodedBadges: [PayloadBadge]? = toolCallHeaderBadges(toolCall)?.map { badge in
                PayloadBadge(text: badge.text, r: badge.color.x, g: badge.color.y, b: badge.color.z, a: badge.color.w)
            }
            let payload = TimelineCustomPayload(
                title: title,
                body: markdown,
                status: toolCall.status.rawValue,
                toolKind: toolCall.kind?.rawValue,
                showsAgentLaneIcon: startsAssistantLane,
                badges: encodedBadges
            )
            return [.custom(
                VVCustomTimelineEntry(
                    id: toolCall.id,
                    kind: "toolCall",
                    payload: encodeCustomPayload(payload, fallback: markdown),
                    revision: revisionKey(markdown + toolCall.id + toolCall.status.rawValue),
                    timestamp: toolCall.timestamp
                )
            )] + inlineDiffEntries(for: toolCall, entryIDPrefix: toolCall.id)

        case .toolCallGroup(let group):
            if group.toolCalls.count == 1, let only = group.toolCalls.first {
                let title = toolCallHeaderTitle(only)
                let markdown = toolCallMarkdown(only)
                let encodedBadges: [PayloadBadge]? = toolCallHeaderBadges(only)?.map { badge in
                    PayloadBadge(text: badge.text, r: badge.color.x, g: badge.color.y, b: badge.color.z, a: badge.color.w)
                }
                let payload = TimelineCustomPayload(
                    title: title,
                    body: markdown,
                    status: only.status.rawValue,
                    toolKind: only.kind?.rawValue,
                    showsAgentLaneIcon: startsAssistantLane,
                    badges: encodedBadges
                )
                return [.custom(
                    VVCustomTimelineEntry(
                        id: group.entryID,
                        kind: "toolCall",
                        payload: encodeCustomPayload(payload, fallback: markdown),
                        revision: revisionKey(markdown + only.id + only.status.rawValue),
                        timestamp: only.timestamp
                    )
                )] + inlineDiffEntries(for: only, entryIDPrefix: group.entryID)
            }
            let isExpanded = expandedToolGroupIDs.contains(group.entryID)
            let title = toolCallGroupTitle(group)
            let markdown = toolCallGroupMarkdown(group, isExpanded: isExpanded)
            let payload = TimelineCustomPayload(
                title: title,
                body: markdown,
                status: toolGroupStatusRawValue(group),
                toolKind: nil,
                showsAgentLaneIcon: startsAssistantLane
            )
            var built: [VVChatTimelineEntry] = [.custom(
                VVCustomTimelineEntry(
                    id: group.entryID,
                    kind: "toolCallGroup",
                    payload: encodeCustomPayload(payload, fallback: markdown),
                    revision: revisionKey(markdown + group.id + (isExpanded ? "-expanded" : "-collapsed")),
                    timestamp: group.timestamp
                )
            )]
            if expandedToolGroupIDs.contains(group.entryID) {
                for call in group.toolCalls {
                    let callTitle = toolCallHeaderTitle(call)
                    let detailMarkdown = toolCallDetailMarkdown(call)
                    let encodedBadges: [PayloadBadge]? = toolCallHeaderBadges(call)?.map { badge in
                        PayloadBadge(text: badge.text, r: badge.color.x, g: badge.color.y, b: badge.color.z, a: badge.color.w)
                    }
                    let detailPayload = TimelineCustomPayload(
                        title: callTitle,
                        body: detailMarkdown,
                        status: call.status.rawValue,
                        toolKind: call.kind?.rawValue,
                        showsAgentLaneIcon: false,
                        badges: encodedBadges
                    )
                    built.append(
                        .custom(
                            VVCustomTimelineEntry(
                                id: "\(group.entryID)::call::\(call.id)",
                                kind: "toolCallDetail",
                                payload: encodeCustomPayload(detailPayload, fallback: detailMarkdown),
                                revision: revisionKey(detailMarkdown + call.id + call.status.rawValue),
                                timestamp: call.timestamp
                            )
                        )
                    )
                    built.append(contentsOf: inlineDiffEntries(
                        for: call,
                        entryIDPrefix: "\(group.entryID)::call::\(call.id)"
                    ))
                }
            }
            return built

        case .turnSummary(let summary):
            let fallback = "\(summary.toolCallCount) tool call\(summary.toolCallCount == 1 ? "" : "s") • \(summary.formattedDuration)"
            let payload = TimelineCustomPayload(
                title: nil,
                body: fallback,
                status: "completed",
                toolKind: nil,
                showsAgentLaneIcon: startsAssistantLane,
                summaryCard: summaryPayloadCard(summary)
            )
            return [.custom(
                VVCustomTimelineEntry(
                    id: summary.entryID,
                    kind: "turnSummary",
                    payload: encodeCustomPayload(payload, fallback: fallback),
                    revision: revisionKey(fallback + summary.id),
                    timestamp: summary.timestamp
                )
            )]
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

    struct PayloadBadge: Codable {
        var text: String
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    struct PayloadSummaryRow: Codable {
        var id: String
        var title: String
        var subtitle: String?
        var iconURL: String?
        var actionURL: String?
        var additionsText: String?
        var deletionsText: String?
    }

    struct PayloadSummaryCard: Codable {
        var title: String
        var subtitle: String?
        var rows: [PayloadSummaryRow]
    }

    struct TimelineCustomPayload: Codable {
        var title: String?
        var body: String
        var status: String?
        var toolKind: String?
        var showsAgentLaneIcon: Bool?
        var badges: [PayloadBadge]?
        var summaryCard: PayloadSummaryCard?
    }

    func encodeCustomPayload(_ payload: TimelineCustomPayload, fallback: String) -> Data {
        if let encoded = try? JSONEncoder().encode(payload) {
            return encoded
        }
        return Data(fallback.utf8)
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
