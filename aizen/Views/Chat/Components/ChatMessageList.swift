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
    let timelineItems: [TimelineItem]
    let isSessionInitializing: Bool
    let pendingPlanRequest: RequestPermissionRequest?
    let selectedAgent: String
    let scrollRequest: ChatSessionViewModel.ScrollRequest?
    var isAutoScrollEnabled: () -> Bool = { true }
    let onAppear: () -> Void
    var onScrollPositionChange: (Bool) -> Void = { _ in }

    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalThemeNameLight") private var terminalThemeNameLight = "Aizen Light"
    @AppStorage("terminalUsePerAppearanceTheme") private var terminalUsePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var controller = VVChatTimelineController(style: .init(), renderWidth: 0)
    @State private var pendingSyncTask: Task<Void, Never>?
    @State private var copiedUserMessageID: String?
    @State private var copiedUserMessageState: CopyFooterState = .idle
    @State private var hoveredCopyUserMessageID: String?
    @State private var copyIndicatorResetTask: Task<Void, Never>?
    @State private var expandedToolGroupIDs: Set<String> = []
    @State private var presentedToolDiff: PresentedToolDiff?

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

    private var timelineSignature: Int {
        var hasher = Hasher()
        hasher.combine(visibleItems.count)
        for item in visibleItems {
            hasher.combine(itemFingerprint(item))
        }
        hasher.combine(planRequestIdentity)
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

    private var timelineStyle: VVChatTimelineStyle {
        let horizontalInset: CGFloat = 10
        let basePointSize = CGFloat(chatFontSize)
        let headerPointSize = max(basePointSize - 1.5, 11.5)
        let timestampPointSize = max(basePointSize - 0.25, 12.5)
        var theme = colorScheme == .dark ? MarkdownTheme.dark : MarkdownTheme.light
        theme.codeColor = markdownInlineCodeColor
        theme.paragraphSpacing = 3
        theme.headingSpacing = 6
        theme.contentPadding = 0
        var draftTheme = theme
        draftTheme.textColor = theme.textColor.withOpacity(theme.textColor.w * 0.72)

        return VVChatTimelineStyle(
            theme: theme,
            draftTheme: draftTheme,
            baseFont: timelineFont(size: basePointSize),
            draftFont: timelineFont(size: basePointSize),
            headerFont: timelineFont(size: headerPointSize, weight: .regular),
            timestampFont: timelineFont(size: timestampPointSize, weight: .medium),
            headerTextColor: colorScheme == .dark ? .rgba(0.98, 0.98, 1.0, 1.0) : .rgba(0.14, 0.16, 0.20, 1.0),
            timestampTextColor: colorScheme == .dark ? .rgba(0.66, 0.69, 0.75, 1.0) : .rgba(0.45, 0.48, 0.54, 1.0),
            userBubbleColor: colorScheme == .dark ? .rgba(0.20, 0.22, 0.25, 0.42) : .rgba(0.91, 0.93, 0.96, 0.62),
            userBubbleBorderColor: colorScheme == .dark ? .rgba(0.64, 0.69, 0.76, 0.18) : .rgba(0.62, 0.66, 0.74, 0.16),
            userBubbleBorderWidth: 0.6,
            userBubbleCornerRadius: 16,
            userBubbleInsets: .init(top: 8, left: 14, bottom: 8, right: 14),
            userBubbleMaxWidth: 560,
            assistantBubbleEnabled: false,
            assistantBubbleMaxWidth: 700,
            assistantBubbleAlignment: .leading,
            systemBubbleEnabled: true,
            systemBubbleColor: .clear,
            systemBubbleBorderColor: .clear,
            systemBubbleBorderWidth: 0,
            systemBubbleInsets: .init(top: 0, left: 0, bottom: 0, right: 0),
            systemBubbleMaxWidth: 760,
            systemBubbleAlignment: .center,
            userHeaderEnabled: false,
            assistantHeaderEnabled: false,
            systemHeaderEnabled: false,
            assistantHeaderTitle: "",
            systemHeaderTitle: "",
            assistantHeaderIconURL: nil,
            headerIconSize: max(13, headerPointSize + 0.5),
            headerIconSpacing: 6,
            userTimestampEnabled: true,
            assistantTimestampEnabled: false,
            systemTimestampEnabled: false,
            userTimestampSuffix: "",
            bubbleMetadataMinWidth: 1,
            headerSpacing: 1,
            footerSpacing: 0,
            timelineInsets: .init(top: 10, left: horizontalInset, bottom: 10, right: horizontalInset + 4),
            messageSpacing: 6,
            userInsets: .init(top: 7, left: horizontalInset, bottom: 7, right: max(horizontalInset, 10)),
            assistantInsets: .init(top: 3, left: 0, bottom: 4, right: 10),
            systemInsets: .init(top: 15, left: 0, bottom: 15, right: 0),
            backgroundColor: .clear
        )
    }

    private var agentLaneIconType: AgentIconType {
        AgentRegistry.shared.getMetadata(for: selectedAgent)?.iconType ?? .builtin(selectedAgent)
    }

    private var agentLaneIconURL: String? {
        ChatTimelineHeaderIconStore.urlString(
            for: agentLaneIconType,
            fallbackAgentId: selectedAgent,
            tintColor: headerIconTintColor,
            targetPointSize: agentLaneIconSize,
            backingScale: timelineBackingScale
        )
    }

    private var agentLaneIconSize: CGFloat {
        max(30, CGFloat(chatFontSize) + 12)
    }

    private var agentLaneIconSpacing: CGFloat {
        max(12, CGFloat(chatFontSize) * 0.5)
    }

    private var agentLaneWidth: CGFloat {
        agentLaneIconSize + agentLaneIconSpacing
    }

    private var headerIconTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedWhite: 0.94, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.18, alpha: 1)
    }

    private var timelineBackingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    private var effectiveTerminalThemeName: String {
        guard terminalUsePerAppearanceTheme else { return terminalThemeName }
        return colorScheme == .dark ? terminalThemeName : terminalThemeNameLight
    }

    private var markdownInlineCodeColor: SIMD4<Float> {
        if let theme = GhosttyThemeParser.loadVVTheme(named: effectiveTerminalThemeName) {
            return simdColor(from: theme.cursorColor)
        }
        return simdColor(from: NSColor.controlAccentColor)
    }

    private func simdColor(from color: NSColor) -> SIMD4<Float> {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return .rgba(Float(r), Float(g), Float(b), 1)
    }

    private func timelineFont(size: CGFloat, weight: NSFont.Weight = .regular) -> VVFont {
        if chatFontFamily == ChatSettings.defaultFontFamily || chatFontFamily == "System Font" {
            return .systemFont(ofSize: size, weight: weight)
        }
        guard let custom = NSFont(name: chatFontFamily, size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        switch weight {
        case .bold, .heavy, .black, .semibold:
            return NSFontManager.shared.convert(custom, toHaveTrait: .boldFontMask)
        default:
            return custom
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if shouldShowLoading {
                AgentLoadingView(agentName: selectedAgent)
            } else {
                VVChatTimelineViewSwiftUI(
                    controller: controller,
                    onStateChange: { state in
                        onScrollPositionChange(state.isPinnedToBottom)
                    },
                    onUserMessageCopyAction: handleUserMessageCopyAction,
                    onUserMessageCopyHoverChange: handleUserMessageCopyHoverChange,
                    onEntryActivate: handleEntryActivate
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $presentedToolDiff) { presented in
            ToolDiffSheet(diff: presented)
                .frame(minWidth: 960, minHeight: 620)
        }
        .onAppear {
            onAppear()
            controller.updateStyle(timelineStyle)
            scheduleSyncTimeline(scrollToBottom: true, debounce: false)
            onScrollPositionChange(controller.state.isPinnedToBottom)
        }
        .onChange(of: timelineSignature) { _, _ in
            scheduleSyncTimeline(scrollToBottom: isAutoScrollEnabled(), debounce: true)
        }
        .onChange(of: scrollRequest?.id) { _, _ in
            handleScrollRequest()
        }
        .onChange(of: colorScheme) { _, _ in
            controller.updateStyle(timelineStyle)
            scheduleSyncTimeline(scrollToBottom: false, debounce: true)
        }
        .onChange(of: chatFontSize) { _, _ in
            controller.updateStyle(timelineStyle)
            scheduleSyncTimeline(scrollToBottom: false, debounce: true)
        }
        .onChange(of: chatFontFamily) { _, _ in
            controller.updateStyle(timelineStyle)
            scheduleSyncTimeline(scrollToBottom: false, debounce: true)
        }
        .onDisappear {
            pendingSyncTask?.cancel()
            copyIndicatorResetTask?.cancel()
        }
    }

    private func handleScrollRequest() {
        guard scrollRequest != nil else { return }
        controller.jumpToLatest()
        onScrollPositionChange(controller.state.isPinnedToBottom)
    }

    private func syncTimeline(scrollToBottom: Bool) {
        controller.setEntries(
            buildEntries(),
            scrollToBottom: scrollToBottom,
            customEntryMessageMapper: customEntryMessageMapper
        )
    }

    private func scheduleSyncTimeline(scrollToBottom: Bool, debounce: Bool) {
        pendingSyncTask?.cancel()

        if !debounce {
            syncTimeline(scrollToBottom: scrollToBottom)
            return
        }

        pendingSyncTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(60))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            syncTimeline(scrollToBottom: scrollToBottom)
        }
    }

    private func handleUserMessageCopyAction(_ messageID: String) {
        if let message = timelineMessage(withID: messageID) {
            let copyText: String
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                copyText = messageMarkdown(message)
            } else {
                copyText = message.content
            }
            guard !copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            Clipboard.copy(copyText)
            copiedUserMessageID = messageID
            copiedUserMessageState = .transition
            scheduleSyncTimeline(scrollToBottom: false, debounce: false)

            copyIndicatorResetTask?.cancel()
            copyIndicatorResetTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(90))
                } catch {
                    return
                }
                guard !Task.isCancelled, copiedUserMessageID == messageID else { return }
                copiedUserMessageState = .confirmed
                scheduleSyncTimeline(scrollToBottom: false, debounce: false)

                do {
                    try await Task.sleep(for: .milliseconds(1110))
                } catch {
                    return
                }
                guard !Task.isCancelled, copiedUserMessageID == messageID else { return }
                copiedUserMessageID = nil
                copiedUserMessageState = .idle
                scheduleSyncTimeline(scrollToBottom: false, debounce: false)
            }
            return
        }

        if let call = toolCallForEntryID(messageID) {
            presentToolDiff(for: call, entryID: messageID)
        }
    }

    private func handleEntryActivate(_ entryID: String) {
        if isToolGroupEntryID(entryID) {
            if expandedToolGroupIDs.contains(entryID) {
                expandedToolGroupIDs.remove(entryID)
            } else {
                expandedToolGroupIDs.insert(entryID)
            }
            scheduleSyncTimeline(scrollToBottom: false, debounce: false)
            return
        }

        if let call = toolCallForEntryID(entryID) {
            presentToolDiff(for: call, entryID: entryID)
        }
    }

    private func presentToolDiff(for toolCall: ToolCall, entryID: String) {
        let diffs = toolDiffContents(for: toolCall)
        guard !diffs.isEmpty else { return }

        let requestedIndex = diffIndexFromEntryID(entryID) ?? 0
        let index = diffs.indices.contains(requestedIndex) ? requestedIndex : 0
        let selected = diffs[index]

        presentedToolDiff = PresentedToolDiff(
            id: "diff-\(toolCall.id)-\(index)",
            title: toolCallDiffRowTitle(
                selected,
                toolCall: toolCall,
                index: index,
                total: diffs.count,
                includeOpenHint: false
            ),
            unifiedDiff: unifiedDiffDocument(for: selected)
        )
    }

    private func handleUserMessageCopyHoverChange(_ messageID: String?) {
        guard hoveredCopyUserMessageID != messageID else { return }
        hoveredCopyUserMessageID = messageID
        scheduleSyncTimeline(scrollToBottom: false, debounce: false)
    }

    private func timelineMessage(withID messageID: String) -> MessageItem? {
        for item in visibleItems {
            guard case .message(let message) = item else { continue }
            guard message.id == messageID else { continue }
            return message
        }
        return nil
    }

    private var customEntryMessageMapper: VVChatTimelineController.CustomEntryMessageMapper {
        { custom in
            let decoded = decodeCustomPayload(from: custom.payload)
            let content = decoded?.body ?? String(data: custom.payload, encoding: .utf8) ?? "[\(custom.kind)]"
            let role: VVChatMessageRole
            let presentation: VVChatMessagePresentation?
            let showsAgentLaneIcon = decoded?.showsAgentLaneIcon == true
            let headerTitle = decoded?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let headerIconURL = toolHeaderIconURL(for: decoded?.toolKind)
            var messageContent = content

            switch custom.kind {
            case "toolCall":
                role = .assistant
                messageContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : content
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: headerIconURL,
                    leadingLaneWidth: agentLaneWidth,
                    leadingIconURL: showsAgentLaneIcon ? agentLaneIconURL : nil,
                    leadingIconSize: showsAgentLaneIcon ? agentLaneIconSize : nil,
                    leadingIconSpacing: showsAgentLaneIcon ? agentLaneIconSpacing : nil,
                    showsTimestamp: false,
                    contentFontScale: 0.70,
                    textOpacityMultiplier: dimmedMetaOpacity,
                    prefixGlyphColor: toolGroupStatusColor(statusRawValue: decoded?.status),
                    prefixGlyphCount: 1
                )
            case "toolCallDetail":
                role = .assistant
                messageContent = ""
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: headerIconURL,
                    leadingLaneWidth: agentLaneWidth,
                    showsTimestamp: false,
                    contentFontScale: 0.72,
                    textOpacityMultiplier: dimmedMetaOpacity * 0.93,
                    prefixGlyphColor: toolGroupStatusColor(statusRawValue: decoded?.status),
                    prefixGlyphCount: 1
                )
            case "toolCallDiff":
                role = .assistant
                messageContent = ""
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: symbolIconURL("doc.text", fallbackID: "tool-diff", tintColor: headerIconTintColor),
                    leadingLaneWidth: agentLaneWidth,
                    showsTimestamp: false,
                    contentFontScale: 0.70,
                    textOpacityMultiplier: dimmedMetaOpacity * 0.96,
                    prefixGlyphColor: toolGroupStatusColor(statusRawValue: decoded?.status),
                    prefixGlyphCount: 1
                )
            case "toolCallGroup":
                role = .assistant
                messageContent = ""
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: headerTitle?.isEmpty == false,
                    headerTitle: headerTitle,
                    headerIconURL: symbolIconURL("square.stack.3d.up", fallbackID: "tool-group", tintColor: headerIconTintColor),
                    leadingLaneWidth: agentLaneWidth,
                    leadingIconURL: showsAgentLaneIcon ? agentLaneIconURL : nil,
                    leadingIconSize: showsAgentLaneIcon ? agentLaneIconSize : nil,
                    leadingIconSpacing: showsAgentLaneIcon ? agentLaneIconSpacing : nil,
                    showsTimestamp: false,
                    contentFontScale: 0.74,
                    textOpacityMultiplier: dimmedMetaOpacity,
                    prefixGlyphColor: toolGroupStatusColor(statusRawValue: decoded?.status),
                    prefixGlyphCount: 1
                )
            case "turnSummary":
                role = .assistant
                presentation = VVChatMessagePresentation(
                    bubbleStyle: nil,
                    showsHeader: false,
                    leadingLaneWidth: agentLaneWidth,
                    leadingIconURL: showsAgentLaneIcon ? agentLaneIconURL : nil,
                    leadingIconSize: showsAgentLaneIcon ? agentLaneIconSize : nil,
                    leadingIconSpacing: showsAgentLaneIcon ? agentLaneIconSpacing : nil,
                    showsTimestamp: false,
                    contentFontScale: 0.84,
                    textOpacityMultiplier: dimmedMetaOpacity,
                    prefixGlyphColor: toolGroupStatusColor(statusRawValue: "completed"),
                    prefixGlyphCount: 1
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
                presentation: presentation
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

    private func symbolIconURL(_ symbolName: String, fallbackID: String? = nil, tintColor: NSColor? = nil) -> String? {
        let resolvedTintColor = tintColor ?? headerIconTintColor
        return ChatTimelineHeaderIconStore.urlString(
            for: .sfSymbol(symbolName),
            fallbackAgentId: fallbackID ?? "symbol-\(symbolName)",
            tintColor: resolvedTintColor
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
        default:
            return "wrench.and.screwdriver"
        }
    }

    private func buildEntries() -> [VVChatTimelineEntry] {
        var entries: [VVChatTimelineEntry] = []
        entries.reserveCapacity(visibleItems.count + (pendingPlanRequest == nil ? 0 : 1))
        var hasRenderedAgentMessageInTurn = false

        for item in visibleItems {
            switch item {
            case .message(let message):
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
            case .toolCall, .toolCallGroup, .turnSummary:
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

        return entries
    }

    private func makeEntries(from item: TimelineItem, startsAssistantLane: Bool) -> [VVChatTimelineEntry] {
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
                    state: message.isComplete ? .final : .draft,
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
                state: message.isComplete ? .final : .draft,
                content: content,
                revision: revisionKey(messageRevisionSeed + "|" + presentationRevisionToken(for: message, startsAssistantLane: startsAssistantLane)),
                timestamp: message.timestamp,
                presentation: messagePresentation(for: message, startsAssistantLane: startsAssistantLane)
            ))]

        case .toolCall(let toolCall):
            let title = toolCallSummaryTitle(toolCall)
            let markdown = toolCallMarkdown(toolCall)
            let payload = TimelineCustomPayload(
                title: title,
                body: markdown,
                status: toolCall.status.rawValue,
                toolKind: toolCall.kind?.rawValue,
                showsAgentLaneIcon: startsAssistantLane
            )
            let built: [VVChatTimelineEntry] = [.custom(
                VVCustomTimelineEntry(
                    id: item.stableId,
                    kind: "toolCall",
                    payload: encodeCustomPayload(payload, fallback: markdown),
                    revision: revisionKey(markdown + toolCall.id + toolCall.status.rawValue),
                    timestamp: toolCall.timestamp
                )
            )]
            let diffs = toolDiffContents(for: toolCall)
            if diffs.isEmpty {
                return built
            }

            var expanded = built
            for (index, diff) in diffs.enumerated() {
                let diffTitle = toolCallDiffRowTitle(
                    diff,
                    toolCall: toolCall,
                    index: index,
                    total: diffs.count,
                    includeOpenHint: true
                )
                let diffPayload = TimelineCustomPayload(
                    title: diffTitle,
                    body: "",
                    status: toolCall.status.rawValue,
                    toolKind: toolCall.kind?.rawValue,
                    showsAgentLaneIcon: false
                )
                expanded.append(
                    .custom(
                        VVCustomTimelineEntry(
                            id: "\(item.stableId)::diff::\(index)",
                            kind: "toolCallDiff",
                            payload: encodeCustomPayload(diffPayload, fallback: diffTitle),
                            revision: revisionKey(diffTitle + "\(toolCall.id)-\(index)-\(diff.path)-\(diff.newText.hashValue)-\(diff.oldText?.hashValue ?? 0)"),
                            timestamp: toolCall.timestamp
                        )
                    )
                )
            }
            return expanded

        case .toolCallGroup(let group):
            if group.toolCalls.count == 1, let only = group.toolCalls.first {
                return makeEntries(from: .toolCall(only), startsAssistantLane: startsAssistantLane)
            }
            let isExpanded = expandedToolGroupIDs.contains(item.stableId)
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
                    id: item.stableId,
                    kind: "toolCallGroup",
                    payload: encodeCustomPayload(payload, fallback: markdown),
                    revision: revisionKey(markdown + group.id),
                    timestamp: group.timestamp
                )
            )]
            if expandedToolGroupIDs.contains(item.stableId) {
                for call in group.toolCalls {
                    let callTitle = toolCallSummaryTitle(call)
                    let detailMarkdown = toolCallDetailMarkdown(call)
                    let detailPayload = TimelineCustomPayload(
                        title: callTitle,
                        body: detailMarkdown,
                        status: call.status.rawValue,
                        toolKind: call.kind?.rawValue,
                        showsAgentLaneIcon: false
                    )
                    built.append(
                        .custom(
                            VVCustomTimelineEntry(
                                id: "\(item.stableId)::call::\(call.id)",
                                kind: "toolCallDetail",
                                payload: encodeCustomPayload(detailPayload, fallback: detailMarkdown),
                                revision: revisionKey(detailMarkdown + call.id + call.status.rawValue),
                                timestamp: call.timestamp
                            )
                        )
                    )

                    let callDiffs = toolDiffContents(for: call)
                    if !callDiffs.isEmpty {
                        for (diffIndex, diff) in callDiffs.enumerated() {
                            let diffTitle = toolCallDiffRowTitle(
                                diff,
                                toolCall: call,
                                index: diffIndex,
                                total: callDiffs.count,
                                includeOpenHint: true
                            )
                            let diffPayload = TimelineCustomPayload(
                                title: diffTitle,
                                body: "",
                                status: call.status.rawValue,
                                toolKind: call.kind?.rawValue,
                                showsAgentLaneIcon: false
                            )
                            built.append(
                                .custom(
                                    VVCustomTimelineEntry(
                                        id: "\(item.stableId)::call::\(call.id)::diff::\(diffIndex)",
                                        kind: "toolCallDiff",
                                        payload: encodeCustomPayload(diffPayload, fallback: diffTitle),
                                        revision: revisionKey(diffTitle + "\(call.id)-\(diffIndex)-\(diff.path)-\(diff.newText.hashValue)-\(diff.oldText?.hashValue ?? 0)"),
                                        timestamp: call.timestamp
                                    )
                                )
                            )
                        }
                    }
                }
            }
            return built

        case .turnSummary(let summary):
            let markdown = turnSummaryMarkdown(summary)
            let payload = TimelineCustomPayload(
                title: nil,
                body: markdown,
                status: "completed",
                toolKind: nil,
                showsAgentLaneIcon: startsAssistantLane
            )
            return [.custom(
                VVCustomTimelineEntry(
                    id: item.stableId,
                    kind: "turnSummary",
                    payload: encodeCustomPayload(payload, fallback: markdown),
                    revision: revisionKey(markdown + summary.id),
                    timestamp: summary.timestamp
                )
            )]
        }
    }

    private func itemFingerprint(_ item: TimelineItem) -> Int {
        switch item {
        case .message(let message):
            return revisionKey("\(message.id)|\(message.isComplete)|\(message.content)|\(message.contentBlocks.count)")
        case .toolCall(let call):
            return revisionKey("\(call.id)|\(call.status.rawValue)|\(call.title)|\(call.content.count)")
        case .toolCallGroup(let group):
            let calls = group.toolCalls.map { "\($0.id):\($0.status.rawValue):\($0.title)" }.joined(separator: "|")
            return revisionKey("\(group.id)|\(group.summaryText)|\(group.hasFailed)|\(group.isInProgress)|\(calls)")
        case .turnSummary(let summary):
            let files = summary.fileChanges.map { "\($0.path):\($0.linesAdded):\($0.linesRemoved)" }.joined(separator: "|")
            return revisionKey("\(summary.id)|\(summary.toolCallCount)|\(summary.formattedDuration)|\(files)")
        }
    }

    private func mapRole(_ role: MessageRole) -> VVChatMessageRole {
        switch role {
        case .user:
            return .user
        case .agent:
            return .assistant
        case .system:
            return .system
        }
    }

    private func messagePresentation(for message: MessageItem, startsAssistantLane: Bool) -> VVChatMessagePresentation? {
        switch message.role {
        case .user:
            return userMessagePresentation(for: message)
        case .agent:
            return VVChatMessagePresentation(
                bubbleStyle: VVChatBubbleStyle(
                    isEnabled: true,
                    color: .clear,
                    borderColor: .clear,
                    borderWidth: 0,
                    cornerRadius: 0,
                    insets: .init(top: 0, left: 0, bottom: 4, right: 0),
                    maxWidth: 760,
                    alignment: .leading
                ),
                showsHeader: false,
                leadingLaneWidth: agentLaneWidth,
                leadingIconURL: startsAssistantLane ? agentLaneIconURL : nil,
                leadingIconSize: startsAssistantLane ? agentLaneIconSize : nil,
                leadingIconSpacing: startsAssistantLane ? agentLaneIconSpacing : nil,
                showsTimestamp: false,
                timestampSuffixIconURL: copySuffixIconURL(for: message.id),
                timestampIconSize: max(13, CGFloat(chatFontSize) - 1),
                timestampIconSpacing: 0
            )
        case .system:
            return nil
        }
    }

    private func presentationRevisionToken(for message: MessageItem, startsAssistantLane: Bool) -> String {
        switch message.role {
        case .user:
            let hoverToken = hoveredCopyUserMessageID == message.id ? "hover" : "rest"
            return "user-copy-\(copyFooterStateToken(for: message.id))-\(hoverToken)-v2"
        case .agent:
            let hoverToken = hoveredCopyUserMessageID == message.id ? "hover" : "rest"
            return "assistant-lane-\(startsAssistantLane ? "start" : "cont")-copy-\(copyFooterStateToken(for: message.id))-\(hoverToken)-v3"
        case .system:
            return "system"
        }
    }

    private func copyFooterStateToken(for messageID: String) -> String {
        guard copiedUserMessageID == messageID else {
            return "idle"
        }
        switch copiedUserMessageState {
        case .idle:
            return "idle"
        case .transition:
            return "transition"
        case .confirmed:
            return "confirmed"
        }
    }

    private func toolCallCompactOutcome(_ toolCall: ToolCall) -> String? {
        if let text = firstTextContent(for: toolCall) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.localizedCaseInsensitiveContains("no matches") {
                    return "0 matches"
                }
                let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).count
                if toolCall.kind == .read {
                    return "\(lines) line\(lines == 1 ? "" : "s")"
                }
            }
        }

        if toolCall.status == .failed {
            return "failed"
        }
        return nil
    }

    private func toolCallAggregateDeltaText(_ toolCall: ToolCall) -> String? {
        guard let delta = toolCallAggregateDelta(toolCall) else { return nil }
        let deltaText = "+\(delta.added) -\(delta.removed)"
        if delta.fileCount > 1 {
            return "\(deltaText) · \(delta.fileCount) files"
        }
        return deltaText
    }

    private func toolCallAggregateDelta(_ toolCall: ToolCall) -> (added: Int, removed: Int, fileCount: Int)? {
        let diffs = toolDiffContents(for: toolCall)
        guard !diffs.isEmpty else { return nil }

        var added = 0
        var removed = 0
        for diff in diffs {
            let delta = toolCallDiffDelta(diff)
            added += delta.added
            removed += delta.removed
        }
        return (added, removed, diffs.count)
    }

    private func toolCallDiffRowTitle(
        _ diff: ToolCallDiff,
        toolCall: ToolCall,
        index: Int,
        total: Int,
        includeOpenHint: Bool
    ) -> String {
        let delta = toolCallDiffDelta(diff)
        let path = compactDisplayPath(diff.path)

        var segments: [String] = ["Diff", path]
        if total > 1 {
            segments.append("\(index + 1)/\(total)")
        }
        segments.append("+\(delta.added) -\(delta.removed)")
        if includeOpenHint {
            segments.append("click to open")
        }
        if toolCall.status == .failed {
            segments.append("failed")
        }
        return segments.joined(separator: " • ")
    }

    private func toolCallDiffDelta(_ diff: ToolCallDiff) -> (added: Int, removed: Int) {
        let oldLines = diff.oldText?.components(separatedBy: "\n") ?? []
        let newLines = diff.newText.components(separatedBy: "\n")
        let oldCount = oldLines.count
        let newCount = newLines.count

        if oldCount == 0 && newCount > 0 {
            return (newCount, 0)
        }
        if newCount == 0 && oldCount > 0 {
            return (0, oldCount)
        }
        if newCount >= oldCount {
            return (newCount - oldCount, 0)
        }
        return (0, oldCount - newCount)
    }

    private func firstTextContent(for toolCall: ToolCall) -> String? {
        for content in toolCall.content {
            guard case .content(let block) = content else { continue }
            if case .text(let text) = block {
                let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return text.text
                }
            }
        }
        return nil
    }

    private func compactDisplayPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawPath }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let components = expanded.split(separator: "/", omittingEmptySubsequences: true)
        if components.count <= 4 {
            return expanded
        }
        return "…/" + components.suffix(4).joined(separator: "/")
    }

    private func turnSummaryMarkdown(_ summary: TurnSummary) -> String {
        var segments: [String] = [
            "✓",
            "\(summary.toolCallCount) tool call\(summary.toolCallCount == 1 ? "" : "s")",
            summary.formattedDuration
        ]

        if !summary.fileChanges.isEmpty {
            let fileSegments = summary.fileChanges.prefix(3).map { change -> String in
                let delta: String
                if change.linesAdded > 0 || change.linesRemoved > 0 {
                    delta = " +\(change.linesAdded)/-\(change.linesRemoved)"
                } else {
                    delta = ""
                }
                return "\(change.filename)\(delta)"
            }
            segments.append(contentsOf: fileSegments)

            if summary.fileChanges.count > 3 {
                segments.append("+\(summary.fileChanges.count - 3)")
            }
        }

        return segments.joined(separator: " • ")
    }

    private func planRequestMarkdown(_ request: RequestPermissionRequest) -> String {
        var sections: [String] = ["**Plan approval requested**"]

        if let message = request.message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(message)
        }

        if let toolCall = request.toolCall,
           let rawInput = toolCall.rawInput?.value as? [String: Any],
           let plan = rawInput["plan"] as? String,
           !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(plan)
        }

        if let options = request.options, !options.isEmpty {
            let optionLines = options.map { "- \($0.name)" }
            sections.append(optionLines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func primaryPath(for toolCall: ToolCall) -> String? {
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

    private func toolDiffContents(for toolCall: ToolCall) -> [ToolCallDiff] {
        toolCall.content.compactMap { content in
            if case .diff(let diff) = content {
                return diff
            }
            return nil
        }
    }

    private func isToolGroupEntryID(_ entryID: String) -> Bool {
        visibleItems.contains { item in
            if case .toolCallGroup = item {
                return item.stableId == entryID
            }
            return false
        }
    }

    private func toolCallForEntryID(_ entryID: String) -> ToolCall? {
        if let groupedCallID = groupedToolCallID(from: entryID) {
            for item in visibleItems {
                guard case .toolCallGroup(let group) = item else { continue }
                if let matched = group.toolCalls.first(where: { $0.id == groupedCallID }) {
                    return matched
                }
            }
            return nil
        }

        if let standaloneCallID = standaloneToolCallDetailID(from: entryID) {
            for item in visibleItems {
                guard case .toolCall(let call) = item else { continue }
                if call.id == standaloneCallID {
                    return call
                }
            }
            return nil
        }

        for item in visibleItems {
            switch item {
            case .toolCall(let call):
                if call.id == entryID {
                    return call
                }
            case .toolCallGroup(let group):
                if let matched = group.toolCalls.first(where: { $0.id == entryID }) {
                    return matched
                }
            case .message, .turnSummary:
                continue
            }
        }
        return nil
    }

    private func groupedToolCallID(from entryID: String) -> String? {
        let marker = "::call::"
        guard let range = entryID.range(of: marker) else { return nil }
        let trailing = String(entryID[range.upperBound...])
        if let suffix = trailing.range(of: "::") {
            return String(trailing[..<suffix.lowerBound])
        }
        return trailing
    }

    private func standaloneToolCallDetailID(from entryID: String) -> String? {
        guard let range = entryID.range(of: "::") else { return nil }
        return String(entryID[..<range.lowerBound])
    }

    private func diffIndexFromEntryID(_ entryID: String) -> Int? {
        guard let range = entryID.range(of: "::diff::", options: .backwards) else {
            return nil
        }
        let trailing = entryID[range.upperBound...]
        return Int(trailing)
    }

    private func unifiedDiffDocument(for diff: ToolCallDiff) -> String {
        let normalizedPath = normalizedDiffPath(diff.path)
        let oldLines = (diff.oldText ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = diff.newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let linePairs = unifiedDiffLines(
            oldLines: oldLines,
            newLines: newLines,
            contextLines: 3,
            maxOutputLines: 8_000
        )

        var output: [String] = [
            "diff --git a/\(normalizedPath) b/\(normalizedPath)",
            "--- a/\(normalizedPath)",
            "+++ b/\(normalizedPath)"
        ]

        output.append("@@ -1,1 +1,1 @@")

        if linePairs.isEmpty {
            output.append(" ")
            return output.joined(separator: "\n")
        }

        for line in linePairs {
            switch line.type {
            case .context:
                output.append(" \(line.content)")
            case .added:
                output.append("+\(line.content)")
            case .deleted:
                output.append("-\(line.content)")
            case .separator:
                output.append("@@ -1,1 +1,1 @@")
            }
        }

        return output.joined(separator: "\n")
    }

    private func normalizedDiffPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "file" }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if !expanded.hasPrefix("/") {
            return expanded
        }

        let cwd = FileManager.default.currentDirectoryPath
        if expanded.hasPrefix(cwd + "/") {
            return String(expanded.dropFirst(cwd.count + 1))
        }

        let pathURL = URL(fileURLWithPath: expanded)
        let components = pathURL.pathComponents.filter { $0 != "/" }
        if components.count >= 3 {
            return components.suffix(3).joined(separator: "/")
        }
        return pathURL.lastPathComponent.isEmpty ? expanded : pathURL.lastPathComponent
    }

    private func unifiedDiffLines(
        oldLines: [String],
        newLines: [String],
        contextLines: Int,
        maxOutputLines: Int
    ) -> [ToolDiffPreviewLine] {
        if oldLines == newLines {
            return []
        }

        let complexityLimit = 350_000
        let complexity = oldLines.count * newLines.count
        if complexity > complexityLimit {
            return fastUnifiedDiffLines(oldLines: oldLines, newLines: newLines, maxOutputLines: maxOutputLines)
        }

        let lcs = longestCommonSubsequence(oldLines, newLines)
        var edits: [(type: ToolDiffPreviewLineType, content: String)] = []
        edits.reserveCapacity(oldLines.count + newLines.count)

        var oldIdx = 0
        var newIdx = 0
        var lcsIdx = 0

        while oldIdx < oldLines.count || newIdx < newLines.count {
            if lcsIdx < lcs.count && oldIdx < oldLines.count && newIdx < newLines.count &&
                oldLines[oldIdx] == lcs[lcsIdx] && newLines[newIdx] == lcs[lcsIdx] {
                edits.append((.context, oldLines[oldIdx]))
                oldIdx += 1
                newIdx += 1
                lcsIdx += 1
            } else if oldIdx < oldLines.count && (lcsIdx >= lcs.count || oldLines[oldIdx] != lcs[lcsIdx]) {
                edits.append((.deleted, oldLines[oldIdx]))
                oldIdx += 1
            } else if newIdx < newLines.count {
                edits.append((.added, newLines[newIdx]))
                newIdx += 1
            }
        }

        return hunkedDiffLines(edits: edits, contextLines: contextLines, maxOutputLines: maxOutputLines)
    }

    private func fastUnifiedDiffLines(
        oldLines: [String],
        newLines: [String],
        maxOutputLines: Int
    ) -> [ToolDiffPreviewLine] {
        var result: [ToolDiffPreviewLine] = []
        result.reserveCapacity(min(maxOutputLines + 1, oldLines.count + newLines.count))

        let oldLimit = min(oldLines.count, maxOutputLines / 2)
        let newLimit = min(newLines.count, maxOutputLines - oldLimit)

        for line in oldLines.prefix(oldLimit) {
            result.append(ToolDiffPreviewLine(type: .deleted, content: line))
        }
        for line in newLines.prefix(newLimit) {
            result.append(ToolDiffPreviewLine(type: .added, content: line))
        }

        if oldLines.count > oldLimit || newLines.count > newLimit {
            result.append(ToolDiffPreviewLine(type: .separator, content: "… truncated …"))
        }

        return result
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let maxMatrixSize = 900
        if a.count > maxMatrixSize || b.count > maxMatrixSize {
            return simpleLCS(a, b)
        }

        let rows = a.count + 1
        let cols = b.count + 1
        var dp = Array(repeating: Array(repeating: 0, count: cols), count: rows)

        for i in 1..<rows {
            for j in 1..<cols {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [String] = []
        var i = a.count
        var j = b.count
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    private func simpleLCS(_ a: [String], _ b: [String]) -> [String] {
        let bSet = Set(b)
        return a.filter { bSet.contains($0) }
    }

    private func hunkedDiffLines(
        edits: [(type: ToolDiffPreviewLineType, content: String)],
        contextLines: Int,
        maxOutputLines: Int
    ) -> [ToolDiffPreviewLine] {
        var changeIndices: [Int] = []
        for (index, edit) in edits.enumerated() where edit.type != .context {
            changeIndices.append(index)
        }
        guard !changeIndices.isEmpty else { return [] }

        var hunks: [[Int]] = []
        var current: [Int] = []
        for index in changeIndices {
            if current.isEmpty {
                current = [index]
            } else if index - (current.last ?? index) <= (contextLines * 2 + 1) {
                current.append(index)
            } else {
                hunks.append(current)
                current = [index]
            }
        }
        if !current.isEmpty {
            hunks.append(current)
        }

        var result: [ToolDiffPreviewLine] = []
        result.reserveCapacity(min(maxOutputLines + hunks.count, edits.count))

        for (hunkIndex, hunk) in hunks.enumerated() {
            let start = max(0, (hunk.first ?? 0) - contextLines)
            let end = min(edits.count - 1, (hunk.last ?? 0) + contextLines)

            if hunkIndex > 0 {
                result.append(ToolDiffPreviewLine(type: .separator, content: "···"))
            }

            for index in start...end {
                result.append(ToolDiffPreviewLine(type: edits[index].type, content: edits[index].content))
                if result.count >= maxOutputLines {
                    result.append(ToolDiffPreviewLine(type: .separator, content: "… truncated …"))
                    return result
                }
            }
        }

        return result
    }

    private func userMessagePresentation(for message: MessageItem) -> VVChatMessagePresentation {
        let copyIconURL = copySuffixIconURL(for: message.id)
        return VVChatMessagePresentation(
            timestampPrefixIconURL: timestampClockIconURL(),
            timestampSuffixIconURL: copyIconURL,
            timestampIconSize: timestampSymbolSize,
            timestampIconSpacing: 6
        )
    }

    private var timestampSymbolSize: CGFloat {
        max(14, CGFloat(chatFontSize) - 0.5)
    }

    private func timestampClockIconURL() -> String? {
        symbolIconURL(
            "clock",
            fallbackID: "timestamp-clock",
            tintColor: timestampIconTintColor
        )
    }

    private func copySuffixIconURL(for messageID: String) -> String? {
        let isHovered = hoveredCopyUserMessageID == messageID
        let isActive = copiedUserMessageID == messageID
        let symbolName: String
        let tintColor: NSColor

        if isActive {
            switch copiedUserMessageState {
            case .idle:
                symbolName = "doc.on.doc"
                tintColor = isHovered ? copyIconHoverTintColor : copyIconIdleTintColor
            case .transition:
                symbolName = "ellipsis"
                tintColor = copyIconHoverTintColor
            case .confirmed:
                symbolName = "checkmark"
                tintColor = copyIconConfirmedTintColor
            }
        } else {
            symbolName = "doc.on.doc"
            tintColor = isHovered ? copyIconHoverTintColor : copyIconIdleTintColor
        }

        return symbolIconURL(
            symbolName,
            fallbackID: "copy-\(symbolName)-\(isHovered ? "hover" : "rest")-\(copyFooterStateToken(for: messageID))",
            tintColor: tintColor
        )
    }

    private var timestampIconTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedWhite: 0.72, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.42, alpha: 1)
    }

    private var copyIconIdleTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedWhite: 0.66, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.45, alpha: 1)
    }

    private var copyIconHoverTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.98, alpha: 1)
        }
        return NSColor(calibratedRed: 0.28, green: 0.38, blue: 0.58, alpha: 1)
    }

    private var copyIconConfirmedTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedRed: 0.42, green: 0.82, blue: 0.56, alpha: 1)
        }
        return NSColor(calibratedRed: 0.14, green: 0.64, blue: 0.28, alpha: 1)
    }

    private func messageMarkdown(_ message: MessageItem) -> String {
        let normalizedContent = normalizedMessageMarkdown(
            message.content,
            role: message.role
        )
        if !normalizedContent.isEmpty {
            return normalizedContent
        }

        var lines: [String] = []
        for block in message.contentBlocks {
            switch block {
            case .text(let text):
                if !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append(text.text)
                }
            case .image:
                lines.append("[Image attachment]")
            case .audio:
                lines.append("[Audio attachment]")
            case .resource(let resource):
                if let uri = resource.resource.uri {
                    lines.append("[Resource](\(uri))")
                } else {
                    lines.append("[Resource attachment]")
                }
            case .resourceLink(let link):
                lines.append("[\(link.name)](\(link.uri))")
            }
        }

        return normalizedMessageMarkdown(lines.joined(separator: "\n\n"), role: message.role)
    }

    private func normalizedMessageMarkdown(_ content: String, role: MessageRole) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard role == .agent else {
            return trimmed
        }

        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Remove accidental uniform left indentation from prose while preserving fenced code blocks.
        var inFence = false
        var commonIndent: Int?
        for line in lines {
            let marker = line.trimmingCharacters(in: .whitespaces)
            if marker.hasPrefix("```") || marker.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence || marker.isEmpty {
                continue
            }
            let indent = leadingHorizontalWhitespaceCount(line)
            commonIndent = min(commonIndent ?? indent, indent)
            if commonIndent == 0 {
                break
            }
        }

        if let commonIndent, commonIndent > 0 {
            inFence = false
            lines = lines.map { line in
                let marker = line.trimmingCharacters(in: .whitespaces)
                if marker.hasPrefix("```") || marker.hasPrefix("~~~") {
                    inFence.toggle()
                    return line
                }
                if inFence || line.isEmpty {
                    return line
                }
                return dropLeadingIndent(line, maxCount: commonIndent)
            }
        }

        // Some agents emit left indentation before prose/headings; strip it (outside fences) to avoid right-shifted blocks.
        inFence = false
        lines = lines.map { line in
            let marker = line.trimmingCharacters(in: .whitespaces)
            if marker.hasPrefix("```") || marker.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }
            if inFence || marker.isEmpty {
                return line
            }
            let indent = leadingHorizontalWhitespaceCount(line)
            guard indent > 0 else {
                return line
            }
            guard let first = marker.first else {
                return line
            }
            let shouldUnindent = first == "#"
                || first == "`"
                || first == "\""
                || first == "'"
                || first.isLetter
                || first.isNumber
            guard shouldUnindent else {
                return line
            }
            return dropLeadingIndent(line, maxCount: indent)
        }

        return lines.joined(separator: "\n")
    }

    private func dropLeadingIndent(_ line: String, maxCount: Int) -> String {
        guard maxCount > 0, !line.isEmpty else { return line }
        var remaining = maxCount
        var index = line.startIndex
        while remaining > 0, index < line.endIndex {
            let char = line[index]
            guard isHorizontalWhitespace(char) else { break }
            index = line.index(after: index)
            remaining -= 1
        }
        return String(line[index...])
    }

    private func leadingHorizontalWhitespaceCount(_ line: String) -> Int {
        var count = 0
        for char in line {
            guard isHorizontalWhitespace(char) else { break }
            count += 1
        }
        return count
    }

    private func isHorizontalWhitespace(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isWhitespace && !CharacterSet.newlines.contains(scalar)
        }
    }

    private func toolCallMarkdown(_ toolCall: ToolCall) -> String {
        toolCallSummaryBody(toolCall)
    }

    private func toolCallSummaryTitle(_ toolCall: ToolCall) -> String {
        var summary = toolCallHumanAction(toolCall)

        if toolCall.kind != .edit {
            if let delta = toolCallAggregateDeltaText(toolCall) {
                summary += " • \(delta)"
            } else if let outcome = toolCallCompactOutcome(toolCall),
                      !summary.localizedCaseInsensitiveContains(outcome) {
                summary += " • \(outcome)"
            }
        }

        switch toolCall.status.rawValue {
        case "failed":
            return "Failed: \(summary)"
        case "in_progress":
            return "\(summary)…"
        case "completed":
            return summary
        default:
            return "\(summary) • \(toolCall.status.rawValue.replacingOccurrences(of: "_", with: " "))"
        }
    }

    private func toolCallDetailMarkdown(_ toolCall: ToolCall) -> String {
        ""
    }

    private func toolCallSummaryBody(_ toolCall: ToolCall) -> String {
        guard let delta = toolCallAggregateDelta(toolCall) else {
            return ""
        }

        var lines: [String] = [
            "```diff",
            "+\(delta.added) lines added",
            "-\(delta.removed) lines removed",
            "```",
            "Click to open full diff"
        ]

        if delta.fileCount > 1 {
            lines.insert("Affects \(delta.fileCount) files", at: 0)
        }

        return lines.joined(separator: "\n")
    }

    private func toolCallGroupTitle(_ group: ToolCallGroup) -> String {
        var segments: [String] = [
            "\(toolGroupStatusMarker(group)) \(group.toolCalls.count) call\(group.toolCalls.count == 1 ? "" : "s")"
        ]
        if let duration = group.formattedDuration {
            segments.append(duration)
        }
        return segments.joined(separator: " • ")
    }

    private func toolCallGroupMarkdown(_ group: ToolCallGroup, isExpanded: Bool) -> String {
        ""
    }

    private func toolCallHumanAction(_ toolCall: ToolCall) -> String {
        switch toolCall.kind {
        case .read:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Read \(target)"
            }
            return "Read a file"
        case .edit:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Edited \(target)"
            }
            return "Edited a file"
        case .delete:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Deleted \(target)"
            }
            return "Deleted a file"
        case .move:
            if let target = toolCallPrimaryTarget(toolCall) {
                return "Moved \(target)"
            }
            return "Moved a file"
        case .search:
            if let target = toolCallPrimaryTarget(toolCall) {
                if target.lowercased().hasPrefix("searched ") {
                    return target
                }
                return "Searched \(target)"
            }
            return "Searched files"
        case .execute:
            return toolCallInputPreview(toolCall) ?? "Ran a shell command"
        case .think:
            return "Reasoned about the next step"
        case .fetch:
            return "Fetched data"
        case .switchMode:
            return "Switched mode"
        case .plan:
            return "Updated plan"
        case .exitPlanMode:
            return "Exited plan mode"
        case .other:
            if let titleAction = humanizedToolTitleAction(toolCall.title) {
                return titleAction
            }
            return sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        case nil:
            if let titleAction = humanizedToolTitleAction(toolCall.title) {
                return titleAction
            }
            return sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        }
    }

    private func toolCallPrimaryTarget(_ toolCall: ToolCall) -> String? {
        if let path = primaryPath(for: toolCall) {
            return compactDisplayPath(path)
        }
        if let input = toolCallInputPreview(toolCall) {
            return abbreviated(input, maxLength: 120)
        }
        return sanitizedToolTitle(toolCall.title)
    }

    private func toolCallInputPreview(_ toolCall: ToolCall) -> String? {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else { return nil }

        if let command = nestedInputString(in: raw, preferredKeys: ["command", "cmd", "shellCommand"]) {
            return humanizedCommandPreview(command)
        }
        if let query = nestedInputString(in: raw, preferredKeys: ["query", "pattern", "glob"]) {
            return "Searched \(abbreviated(query, maxLength: 80))"
        }
        if let path = nestedInputString(in: raw, preferredKeys: ["path", "file", "filePath", "filepath"]) {
            return compactDisplayPath(path)
        }

        return nil
    }

    private func nestedInputString(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = recursiveStringValue(dict[key], preferredKey: key) {
                return value
            }
        }
        return nil
    }

    private func recursiveStringValue(_ value: Any?, preferredKey: String, depth: Int = 0) -> String? {
        guard depth < 8, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dict = value as? [String: Any] {
            if let nested = recursiveStringValue(dict[preferredKey], preferredKey: preferredKey, depth: depth + 1) {
                return nested
            }
            for fallback in ["value", "text", "path", "query", "pattern", "command"] {
                if let nested = recursiveStringValue(dict[fallback], preferredKey: preferredKey, depth: depth + 1) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let nested = recursiveStringValue(item, preferredKey: preferredKey, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }

    private func humanizedCommandPreview(_ rawCommand: String) -> String {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "Ran a shell command" }

        let primary = command.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? command
        let tokens = primary.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = tokens.first?.lowercased() else {
            return "Ran a shell command"
        }

        switch executable {
        case "ls":
            let args = Array(tokens.dropFirst())
            if let target = lastNonOptionToken(in: args) {
                return "Listed \(compactDisplayPath(unquoted(target)))"
            }
            return "Listed files"
        case "find":
            if let target = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                return "Searched \(compactDisplayPath(unquoted(target)))"
            }
            return "Searched files"
        case "cat", "head", "tail":
            if let target = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                return "Read \(compactDisplayPath(unquoted(target)))"
            }
            return "Read command output"
        case "rg", "grep":
            return "Searched text"
        default:
            return "Ran shell command"
        }
    }

    private func lastNonOptionToken(in tokens: [String]) -> String? {
        tokens.reversed().first { !$0.hasPrefix("-") }
    }

    private func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func humanizedToolTitleAction(_ rawTitle: String) -> String? {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let kind = trimmed[..<colon].lowercased()
        let rawTarget = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let target = unquoted(rawTarget)

        switch kind {
        case "readfile", "read":
            return target.isEmpty ? "Read a file" : "Read \(compactDisplayPath(target))"
        case "strreplacefile", "editfile", "writefile", "replacefile", "edit":
            return target.isEmpty ? "Edited a file" : "Edited \(compactDisplayPath(target))"
        case "glob", "search", "find":
            return target.isEmpty ? "Searched files" : "Searched \(abbreviated(target, maxLength: 80))"
        case "shell", "exec", "command":
            return target.isEmpty ? "Ran shell command" : humanizedCommandPreview(target)
        case "list", "ls":
            return target.isEmpty ? "Listed files" : "Listed \(compactDisplayPath(target))"
        default:
            return nil
        }
    }

    private func sanitizedToolTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return nil
        }
        if trimmed.contains("\"command\"") || trimmed.contains("\"path\"") {
            return nil
        }
        return abbreviated(trimmed, maxLength: 120)
    }

    private func abbreviated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<index]) + "…"
    }

    private struct TimelineCustomPayload: Codable {
        var title: String?
        var body: String
        var status: String?
        var toolKind: String?
        var showsAgentLaneIcon: Bool?
    }

    private func encodeCustomPayload(_ payload: TimelineCustomPayload, fallback: String) -> Data {
        if let encoded = try? JSONEncoder().encode(payload) {
            return encoded
        }
        return Data(fallback.utf8)
    }

    private func decodeCustomPayload(from data: Data) -> TimelineCustomPayload? {
        try? JSONDecoder().decode(TimelineCustomPayload.self, from: data)
    }

    private func toolGroupStatusRawValue(_ group: ToolCallGroup) -> String {
        if group.hasFailed { return "failed" }
        if group.isInProgress { return "in_progress" }
        return "completed"
    }

    private func toolGroupStatusMarker(_ group: ToolCallGroup) -> String {
        if group.hasFailed { return "✕" }
        if group.isInProgress { return "◌" }
        return "✓"
    }

    private func toolGroupStatusColor(statusRawValue: String?) -> SIMD4<Float> {
        switch statusRawValue {
        case "failed":
            return colorScheme == .dark ? .rgba(0.92, 0.42, 0.44, 1) : .rgba(0.82, 0.24, 0.28, 1)
        case "in_progress":
            return colorScheme == .dark ? .rgba(0.98, 0.78, 0.36, 1) : .rgba(0.88, 0.62, 0.06, 1)
        default:
            return colorScheme == .dark ? .rgba(0.42, 0.82, 0.52, 1) : .rgba(0.14, 0.64, 0.24, 1)
        }
    }

    private var dimmedMetaOpacity: Float {
        colorScheme == .dark ? 0.60 : 0.67
    }

    private func revisionKey(_ value: String) -> Int {
        let hashed = value.hashValue
        if hashed == Int.min {
            return Int.max
        }
        return abs(hashed)
    }
}

private enum ToolDiffPreviewLineType {
    case context
    case added
    case deleted
    case separator
}

private struct ToolDiffPreviewLine {
    let type: ToolDiffPreviewLineType
    let content: String
}

private enum CopyFooterState {
    case idle
    case transition
    case confirmed
}

private struct PresentedToolDiff: Identifiable {
    let id: String
    let title: String
    let unifiedDiff: String
}

private struct ToolDiffSheet: View {
    let diff: PresentedToolDiff

    @AppStorage("editorFontFamily") private var editorFontFamily = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize = 12.0
    @AppStorage("editorTheme") private var editorTheme: String = "Aizen Dark"
    @AppStorage("editorThemeLight") private var editorThemeLight: String = "Aizen Light"
    @AppStorage("editorUsePerAppearanceTheme") private var usePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return editorTheme }
        return colorScheme == .dark ? editorTheme : editorThemeLight
    }

    private var theme: VVTheme {
        GhosttyThemeParser.loadVVTheme(named: effectiveThemeName)
            ?? (colorScheme == .dark ? .defaultDark : .defaultLight)
    }

    private var configuration: VVConfiguration {
        let font = NSFont(name: editorFontFamily, size: max(editorFontSize - 1, 10))
            ?? .monospacedSystemFont(ofSize: max(editorFontSize - 1, 10), weight: .regular)

        return VVConfiguration.default
            .with(font: font)
            .with(showLineNumbers: true)
            .with(showGutter: true)
            .with(showGitGutter: false)
            .with(wrapLines: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(diff.title.isEmpty ? "Tool Diff" : diff.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            VVDiffView(unifiedDiff: diff.unifiedDiff)
                .theme(theme)
                .configuration(configuration)
                .renderStyle(.unifiedTable)
                .syntaxHighlighting(true)
                .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

// MARK: - Processing Indicator (fixed above input bar)

private enum ChatTimelineHeaderIconStore {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()
    private static let fileManager = FileManager.default
    private static let renderVersion = "v5"
    private static let directoryURL: URL = {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("aizen-chat-header-icons", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func urlString(for iconType: AgentIconType, fallbackAgentId: String) -> String? {
        urlString(for: iconType, fallbackAgentId: fallbackAgentId, tintColor: nil)
    }

    static func urlString(
        for iconType: AgentIconType,
        fallbackAgentId: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat? = nil,
        backingScale: CGFloat? = nil
    ) -> String? {
        let cacheKey = key(
            for: iconType,
            fallbackAgentId: fallbackAgentId,
            tintColor: tintColor,
            targetPointSize: targetPointSize,
            backingScale: backingScale
        )

        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let path = iconPath(
            for: iconType,
            fallbackAgentId: fallbackAgentId,
            cacheKey: cacheKey,
            tintColor: tintColor,
            targetPointSize: targetPointSize,
            backingScale: backingScale
        ) else {
            return nil
        }

        lock.lock()
        cache[cacheKey] = path
        lock.unlock()
        return path
    }

    private static func key(
        for iconType: AgentIconType,
        fallbackAgentId: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> String {
        let tintKey = tintColorKey(tintColor)
        let sizeKey = targetPointSizeKey(targetPointSize)
        let scaleKey = backingScaleKey(backingScale)
        switch iconType {
        case .builtin(let name):
            return "\(renderVersion)-builtin-\(name.lowercased())-\(sizeKey)-\(scaleKey)-\(tintKey)"
        case .sfSymbol(let symbol):
            return "\(renderVersion)-sf-\(symbol)-\(sizeKey)-\(scaleKey)-\(tintKey)"
        case .customImage(let data):
            return "\(renderVersion)-custom-\(data.hashValue)-\(sizeKey)-\(scaleKey)-\(tintKey)"
        }
    }

    private static func iconPath(
        for iconType: AgentIconType,
        fallbackAgentId: String,
        cacheKey: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> String? {
        switch iconType {
        case .builtin(let name):
            guard let image = builtinImage(named: name, fallbackAgentId: fallbackAgentId) else {
                return nil
            }
            return writeRasterImage(
                image,
                cacheKey: cacheKey,
                tintColor: tintColor,
                targetPointSize: targetPointSize,
                backingScale: backingScale
            )
        case .sfSymbol(let symbol):
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
                return nil
            }
            let configured = configuredSymbolImage(
                image,
                pointSize: max(12, targetPointSize ?? 19),
                weight: .regular
            )
            return writeRasterImage(
                configured,
                cacheKey: cacheKey,
                tintColor: tintColor,
                targetPointSize: targetPointSize,
                backingScale: backingScale
            )
        case .customImage(let data):
            if let image = NSImage(data: data) {
                return writeRasterImage(
                    image,
                    cacheKey: cacheKey,
                    tintColor: tintColor,
                    targetPointSize: targetPointSize,
                    backingScale: backingScale
                )
            }
            return writeRawImageData(data, cacheKey: cacheKey)
        }
    }

    private static func builtinImage(named name: String, fallbackAgentId: String) -> NSImage? {
        for candidate in builtinAssetCandidates(for: name, fallbackAgentId: fallbackAgentId) {
            if let image = NSImage(named: candidate) {
                return image
            }
        }
        return nil
    }

    private static func builtinAssetCandidates(for name: String, fallbackAgentId: String) -> [String] {
        let normalized = name.lowercased()
        var candidates: [String]

        switch normalized {
        case "codex", "openai":
            candidates = ["openai", "codex"]
        case "claude":
            candidates = ["claude"]
        case "gemini":
            candidates = ["gemini"]
        case "copilot":
            candidates = ["copilot"]
        case "droid":
            candidates = ["droid"]
        case "kimi":
            candidates = ["kimi"]
        case "opencode":
            candidates = ["opencode"]
        case "vibe", "mistral":
            candidates = ["mistral"]
        case "qwen":
            candidates = ["qwen"]
        default:
            candidates = [normalized]
        }

        if !fallbackAgentId.isEmpty {
            candidates.append(fallbackAgentId.lowercased())
        }
        return candidates
    }

    private static func writeRawImageData(_ data: Data, cacheKey: String) -> String? {
        let ext = isSVGData(data) ? "svg" : "img"
        let fileURL = directoryURL.appendingPathComponent("\(cacheKey).\(ext)")

        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return nil
            }
        }

        return fileURL.path
    }

    private static func writeRasterImage(
        _ image: NSImage,
        cacheKey: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> String? {
        guard let data = rasterizedPNGData(
            for: image,
            tintColor: tintColor,
            targetPointSize: targetPointSize,
            backingScale: backingScale
        ) else {
            return nil
        }
        let fileURL = directoryURL.appendingPathComponent("\(cacheKey).png")
        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return nil
            }
        }
        return fileURL.path
    }

    private static func isSVGData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        let lower = text.lowercased()
        return lower.contains("<svg") || lower.contains("image/svg+xml")
    }

    private static func tintColorKey(_ tintColor: NSColor?) -> String {
        guard let tintColor,
              let color = tintColor.usingColorSpace(.sRGB) else {
            return "notint"
        }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        let a = Int((color.alphaComponent * 255).rounded())
        return "\(r)-\(g)-\(b)-\(a)"
    }

    private static func targetPointSizeKey(_ size: CGFloat?) -> String {
        guard let size, size > 0 else { return "default" }
        return String(Int((size * 100).rounded()))
    }

    private static func backingScaleKey(_ scale: CGFloat?) -> String {
        guard let scale, scale > 0 else { return "default" }
        return String(Int((scale * 100).rounded()))
    }

    private static func rasterizedPNGData(
        for image: NSImage,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> Data? {
        let sourceSize = normalizedSourceSize(for: image)
        let renderPointSize = resolvedRenderPointSize(
            sourceSize: sourceSize,
            targetPointSize: targetPointSize
        )
        let scale = max(1, backingScale ?? NSScreen.main?.backingScaleFactor ?? 2)
        let pixelWidth = max(1, Int((renderPointSize.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((renderPointSize.height * scale).rounded(.up)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmap.size = renderPointSize

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let bounds = NSRect(origin: .zero, size: renderPointSize)
        NSColor.clear.setFill()
        bounds.fill()

        let drawRect = aspectFitRect(contentSize: sourceSize, in: bounds)
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)

        if let tintColor {
            tintColor.setFill()
            bounds.fill(using: .sourceIn)
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func normalizedSourceSize(for image: NSImage) -> NSSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           cgImage.width > 0, cgImage.height > 0 {
            let scale = image.representations
                .compactMap { $0.pixelsWide > 0 ? CGFloat($0.pixelsWide) / max(1, $0.size.width) : nil }
                .max() ?? NSScreen.main?.backingScaleFactor ?? 2
            return NSSize(width: CGFloat(cgImage.width) / max(1, scale), height: CGFloat(cgImage.height) / max(1, scale))
        }
        if image.size.width > 0 && image.size.height > 0 {
            return image.size
        }
        return NSSize(width: 16, height: 16)
    }

    private static func resolvedRenderPointSize(sourceSize: NSSize, targetPointSize: CGFloat?) -> NSSize {
        guard let targetPointSize, targetPointSize > 0 else {
            return sourceSize
        }
        return NSSize(width: targetPointSize, height: targetPointSize)
    }

    private static func aspectFitRect(contentSize: NSSize, in bounds: NSRect) -> NSRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return bounds }
        let widthRatio = bounds.width / contentSize.width
        let heightRatio = bounds.height / contentSize.height
        let scale = min(widthRatio, heightRatio)
        let drawSize = NSSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return NSRect(
            x: bounds.minX + (bounds.width - drawSize.width) * 0.5,
            y: bounds.minY + (bounds.height - drawSize.height) * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private static func configuredSymbolImage(_ image: NSImage, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage {
        let config = NSImage.SymbolConfiguration(
            pointSize: max(12, pointSize),
            weight: weight,
            scale: .medium
        )
        return image.withSymbolConfiguration(config) ?? image
    }
}

struct ChatProcessingIndicator: View {
    let currentThought: String?
    let renderInlineMarkdown: (String) -> AttributedString

    @State private var cachedThoughtText: String?
    @State private var cachedThoughtRendered: AttributedString = AttributedString("")

    var body: some View {
        HStack(spacing: 8) {
            ChatProcessingSpinner()

            if cachedThoughtText != nil {
                Text(cachedThoughtRendered)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .modifier(
                        ShimmerEffect(
                            bandSize: 0.38,
                            duration: 2.2,
                            baseOpacity: 0.08,
                            highlightOpacity: 1.0
                        )
                    )
            } else {
                Text("chat.agent.thinking", bundle: .main)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .modifier(
                        ShimmerEffect(
                            bandSize: 0.38,
                            duration: 2.2,
                            baseOpacity: 0.08,
                            highlightOpacity: 1.0
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updateCachedThought(currentThought)
        }
        .onChange(of: currentThought) { _, newThought in
            updateCachedThought(newThought)
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

private struct ChatProcessingSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 0.9)
            .stroke(
                Color.secondary.opacity(0.85),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                reduceMotion ? .none : .linear(duration: 0.9).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
            }
    }
}
