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

    @AppStorage(AppearanceSettings.markdownFontFamilyKey) private var markdownFontFamily = AppearanceSettings.defaultMarkdownFontFamily
    @AppStorage(AppearanceSettings.markdownFontSizeKey) private var markdownFontSize = AppearanceSettings.defaultMarkdownFontSize
    @AppStorage(AppearanceSettings.markdownParagraphSpacingKey) private var markdownParagraphSpacing = AppearanceSettings.defaultMarkdownParagraphSpacing
    @AppStorage(AppearanceSettings.markdownHeadingSpacingKey) private var markdownHeadingSpacing = AppearanceSettings.defaultMarkdownHeadingSpacing
    @AppStorage(AppearanceSettings.markdownContentPaddingKey) private var markdownContentPadding = AppearanceSettings.defaultMarkdownContentPadding
    @AppStorage(AppearanceSettings.themeNameKey) private var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) private var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var terminalUsePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var controller = VVChatTimelineController(style: .init(), renderWidth: 0)
    @State private var appliedEntries: [VVChatTimelineEntry] = []
    @State private var lastBuildMetadata = TimelineBuildMetadata()
    @State private var lastReportedTimelineState: VVChatTimelineState?
    @State private var copiedUserMessageID: String?
    @State private var copiedUserMessageState: CopyFooterState = .idle
    @State private var hoveredCopyUserMessageID: String?
    @State private var copyIndicatorResetTask: Task<Void, Never>?
    @State private var expandedToolGroupIDs: Set<String> = []
    @State private var suppressNextTimelineSignatureSync = false

    private var shouldShowLoading: Bool {
        isSessionInitializing && messages.isEmpty && toolCalls.isEmpty
    }

    private var topLevelToolCalls: [ToolCall] {
        toolCalls.filter { $0.parentToolCallId == nil }
    }

    private var latestCopyableAgentMessageID: String? {
        messages.reversed().first { message in
            guard message.role == .agent else { return false }
            return hasCopyableMessageContent(message)
        }?.id
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

    private var timelineStyleSignature: Int {
        var hasher = Hasher()
        hasher.combine(colorScheme)
        hasher.combine(markdownFontSize)
        hasher.combine(markdownFontFamily)
        hasher.combine(markdownParagraphSpacing)
        hasher.combine(markdownHeadingSpacing)
        hasher.combine(markdownContentPadding)
        hasher.combine(effectiveTerminalThemeName)
        return hasher.finalize()
    }

    private var timelineStyle: VVChatTimelineStyle {
        let horizontalInset: CGFloat = 10
        let basePointSize = CGFloat(markdownFontSize)
        let headerPointSize = max(basePointSize - 1.5, 11.5)
        let timestampPointSize = max(basePointSize - 0.25, 12.5)
        let theme = timelineMarkdownTheme
        let draftTheme = theme

        return VVChatTimelineStyle(
            theme: theme,
            draftTheme: draftTheme,
            baseFont: timelineFont(size: basePointSize),
            draftFont: timelineFont(size: basePointSize),
            headerFont: timelineFont(size: headerPointSize, weight: .regular),
            timestampFont: timelineFont(size: timestampPointSize, weight: .medium),
            headerTextColor: colorScheme == .dark ? .rgba(0.98, 0.98, 1.0, 1.0) : .rgba(0.14, 0.16, 0.20, 1.0),
            timestampTextColor: colorScheme == .dark ? .rgba(0.66, 0.69, 0.75, 1.0) : .rgba(0.45, 0.48, 0.54, 1.0),
            userBubbleColor: userBubbleFillColor,
            userBubbleBorderColor: userBubbleStrokeColor,
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
        AgentRegistry.shared.getMetadata(for: selectedAgent)?.iconType ?? .sfSymbol("brain.head.profile")
    }

    private var agentLaneIconURL: String? {
        nil
    }

    private var agentLaneIconSize: CGFloat {
        0
    }

    private var agentLaneIconSpacing: CGFloat {
        0
    }

    private var agentLaneWidth: CGFloat {
        0
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
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    private var activeTerminalVVTheme: VVTheme? {
        GhosttyThemeParser.loadVVTheme(named: effectiveTerminalThemeName)
    }

    private var markdownInlineCodeColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.cursorColor)
        }
        return simdColor(from: NSColor.controlAccentColor)
    }

    private var timelineMarkdownTheme: MarkdownTheme {
        _ = markdownParagraphSpacing
        _ = markdownHeadingSpacing
        _ = markdownContentPadding
        var theme = AppearanceSettings.resolvedMarkdownTheme(colorScheme: colorScheme)
        theme.codeColor = markdownInlineCodeColor
        return theme
    }

    private var userBubbleFillColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.backgroundColor).withOpacity(colorScheme == .dark ? 0.78 : 0.92)
        }
        return colorScheme == .dark ? .rgba(0.20, 0.22, 0.25, 0.42) : .rgba(0.91, 0.93, 0.96, 0.62)
    }

    private var userBubbleStrokeColor: SIMD4<Float> {
        let divider = GhosttyThemeParser.loadDividerColor(named: effectiveTerminalThemeName)
        return simdColor(from: divider).withOpacity(colorScheme == .dark ? 0.32 : 0.18)
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
        if markdownFontFamily == AppearanceSettings.defaultMarkdownFontFamily || markdownFontFamily == AppearanceSettings.systemFontFamily {
            return .systemFont(ofSize: size, weight: weight)
        }
        guard let custom = NSFont(name: markdownFontFamily, size: size) else {
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

    private func syncTimeline(scrollToBottom: Bool) {
        let build = buildTimeline()
        lastBuildMetadata = build.metadata
        apply(entries: build.entries, scrollToBottom: scrollToBottom)
    }

    private func apply(entries newEntries: [VVChatTimelineEntry], scrollToBottom: Bool) {
        defer { appliedEntries = newEntries }

        if appliedEntries.isEmpty {
            controller.setEntries(
                newEntries,
                scrollToBottom: scrollToBottom,
                customEntryMessageMapper: customEntryMessageMapper
            )
            return
        }

        if canApplyIncrementally(from: appliedEntries, to: newEntries) {
            let oldCount = appliedEntries.count
            let newCount = newEntries.count
            let replacements = makeEntryReplacements(from: appliedEntries, to: newEntries)

            if !replacements.isEmpty {
                applyEntryReplacements(replacements, scrollToBottom: scrollToBottom)
            }

            if newCount > oldCount {
                for entry in newEntries[oldCount...] {
                    append(entry)
                }
            }
            return
        }

        // Structural change — use range replacement instead of full setEntries rebuild.
        // This matches the VVDevKit playground pattern: replaceEntries preserves layout
        // continuity and render caches, while setEntries invalidates everything.
        if let anchorID = stableAnchorID(from: appliedEntries, to: newEntries) {
            controller.prepareLayoutTransition(anchorItemID: anchorID)
        }
        controller.replaceEntries(
            in: 0..<controller.entries.count,
            with: newEntries,
            scrollToBottom: scrollToBottom,
            markUnread: false
        )
    }

    private func stableAnchorID(from oldEntries: [VVChatTimelineEntry], to newEntries: [VVChatTimelineEntry]) -> String? {
        let newIDs = Set(newEntries.map(\.id))
        // Find the first old entry that still exists in the new set — best scroll anchor
        for entry in oldEntries {
            if newIDs.contains(entry.id) {
                return entry.id
            }
        }
        return newEntries.first?.id
    }

    private func canApplyIncrementally(from oldEntries: [VVChatTimelineEntry], to newEntries: [VVChatTimelineEntry]) -> Bool {
        guard !oldEntries.isEmpty else { return false }
        guard newEntries.count >= oldEntries.count else { return false }

        let prefixCount = min(oldEntries.count, newEntries.count)
        for index in 0..<prefixCount {
            if oldEntries[index].id != newEntries[index].id {
                return false
            }
        }
        return true
    }

    private func append(_ entry: VVChatTimelineEntry) {
        prepareAppendTransition()
        switch entry {
        case .message(let message):
            controller.appendMessage(message)
        case .custom(let custom):
            controller.appendCustomEntry(custom)
        }
    }

    private struct EntryReplacement {
        let id: String
        let oldEntry: VVChatTimelineEntry
        let newEntry: VVChatTimelineEntry
    }

    private func prepareAppendTransition() {
        let anchorID = controller.entries.last?.id ?? appliedEntries.last?.id
        if let anchorID {
            controller.prepareLayoutTransition(anchorItemID: anchorID)
        }
    }

    private func makeEntryReplacements(
        from oldEntries: [VVChatTimelineEntry],
        to newEntries: [VVChatTimelineEntry]
    ) -> [EntryReplacement] {
        let prefixCount = min(oldEntries.count, newEntries.count)
        var replacements: [EntryReplacement] = []
        replacements.reserveCapacity(prefixCount)

        for index in 0..<prefixCount {
            if entryRevision(oldEntries[index]) != entryRevision(newEntries[index]) {
                replacements.append(
                    EntryReplacement(
                        id: oldEntries[index].id,
                        oldEntry: oldEntries[index],
                        newEntry: newEntries[index]
                    )
                )
            }
        }

        return replacements
    }

    private func applyEntryReplacements(_ replacements: [EntryReplacement], scrollToBottom: Bool) {
        for replacement in replacements {
            if applyDraftMessageUpdateIfPossible(replacement) {
                continue
            }
            controller.prepareLayoutTransition(anchorItemID: replacement.id)
            controller.replaceEntry(
                id: replacement.id,
                with: replacement.newEntry,
                scrollToBottom: scrollToBottom
            )
        }
    }

    private func applyDraftMessageUpdateIfPossible(_ replacement: EntryReplacement) -> Bool {
        guard case .message(let oldMessage) = replacement.oldEntry,
              case .message(let newMessage) = replacement.newEntry else {
            return false
        }
        guard oldMessage.id == newMessage.id else { return false }
        guard oldMessage.role == .assistant, newMessage.role == .assistant else { return false }
        guard oldMessage.state == .draft, newMessage.state == .draft else { return false }
        guard oldMessage.presentation == newMessage.presentation else { return false }
        guard oldMessage.customContent == newMessage.customContent else { return false }
        guard oldMessage.timestamp == newMessage.timestamp else { return false }

        controller.updateDraftMessage(id: newMessage.id, content: newMessage.content, throttle: true)
        return true
    }

    private func reportTimelineStateIfNeeded(_ state: VVChatTimelineState) {
        guard lastReportedTimelineState != state else { return }
        lastReportedTimelineState = state
        onTimelineStateChange(state)
    }

    private func entryRevision(_ entry: VVChatTimelineEntry) -> Int {
        switch entry {
        case .message(let message):
            return message.revision
        case .custom(let custom):
            return custom.revision
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
            syncTimeline(scrollToBottom: false)

            copyIndicatorResetTask?.cancel()
            copyIndicatorResetTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(90))
                } catch {
                    return
                }
                guard !Task.isCancelled, copiedUserMessageID == messageID else { return }
                copiedUserMessageState = .confirmed
                syncTimeline(scrollToBottom: false)

                do {
                    try await Task.sleep(for: .milliseconds(1110))
                } catch {
                    return
                }
                guard !Task.isCancelled, copiedUserMessageID == messageID else { return }
                copiedUserMessageID = nil
                copiedUserMessageState = .idle
                syncTimeline(scrollToBottom: false)
            }
            return
        }

    }

    private func handleEntryActivate(_ entryID: String) {
        if isToolGroupEntryID(entryID) {
            toggleToolGroupEntry(entryID)
            return
        }

    }

    private func toggleToolGroupEntry(_ entryID: String) {
        suppressNextTimelineSignatureSync = true
        controller.prepareLayoutTransition(anchorItemID: entryID)
        if expandedToolGroupIDs.contains(entryID) {
            expandedToolGroupIDs.remove(entryID)
        } else {
            expandedToolGroupIDs.insert(entryID)
        }

        guard let group = toolCallGroup(forEntryID: entryID),
              let replacementRange = toolCallGroupEntryRange(for: entryID, in: appliedEntries) else {
            syncTimeline(scrollToBottom: false)
            return
        }

        let replacementEntries = makeEntries(from: .toolCallGroup(group), startsAssistantLane: false)
        controller.replaceEntries(
            in: replacementRange,
            with: replacementEntries,
            scrollToBottom: false,
            markUnread: false
        )
        appliedEntries.replaceSubrange(replacementRange, with: replacementEntries)
    }

    private func handleTimelineLinkActivate(_ rawLink: String) {
        guard let url = URL(string: rawLink) else { return }

        switch url.scheme?.lowercased() {
        case "aizen-file":
            guard let path = destinationPath(from: url) else { return }
            NotificationCenter.default.post(
                name: .openFileInEditor,
                object: nil,
                userInfo: ["path": path]
            )
        case "aizen":
            DeepLinkHandler.shared.handle(url)
        default:
            NSWorkspace.shared.open(url)
        }
    }

    private func handleUserMessageCopyHoverChange(_ messageID: String?) {
        guard hoveredCopyUserMessageID != messageID else { return }
        hoveredCopyUserMessageID = messageID
    }

    private func timelineMessage(withID messageID: String) -> MessageItem? {
        lastBuildMetadata.messagesByID[messageID]
    }

    private func toolCallGroup(forEntryID entryID: String) -> ToolCallGroup? {
        for item in assembleTimelineSourceItems() {
            guard case .toolCallGroup(let group) = item, group.entryID == entryID else { continue }
            return group
        }
        return nil
    }

    private func toolCallGroupEntryRange(
        for groupEntryID: String,
        in entries: [VVChatTimelineEntry]
    ) -> Range<Int>? {
        guard let lowerBound = entries.firstIndex(where: { $0.id == groupEntryID }) else {
            return nil
        }
        let detailPrefix = "\(groupEntryID)::"
        var upperBound = lowerBound + 1
        while upperBound < entries.count, entries[upperBound].id.hasPrefix(detailPrefix) {
            upperBound += 1
        }
        return lowerBound..<upperBound
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

    private func symbolIconURL(_ symbolName: String, fallbackID: String? = nil, tintColor: NSColor? = nil, pointSize: CGFloat? = nil) -> String? {
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

    private struct TimelineBuildMetadata {
        var messagesByID: [String: MessageItem] = [:]
        var toolCallsByEntryID: [String: ToolCall] = [:]
        var groupEntryIDs: Set<String> = []
    }

    private enum TimelineSourceItem {
        case message(MessageItem)
        case toolCall(ToolCall)
        case toolCallGroup(ToolCallGroup)
        case turnSummary(TurnSummary)
    }

    private struct FileChangeSummary: Identifiable {
        let path: String
        let isNew: Bool
        var linesAdded: Int
        var linesRemoved: Int

        var id: String { path }
    }

    private struct TurnSummary: Identifiable {
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

    private struct ToolCallGroup: Identifiable {
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

    private enum OrderedTimelineSource {
        case message(MessageItem)
        case toolCall(ToolCall)
    }

    private struct OrderedTimelineItem {
        let source: OrderedTimelineSource
        let timestamp: Date
        let priority: Int
        let sequence: Int
    }

    private func assembleTimelineSourceItems() -> [TimelineSourceItem] {
        let orderedSources = orderedTimelineSources()

        var items: [TimelineSourceItem] = []
        var toolCallBuffer: [ToolCall] = []
        var turnToolCalls: [ToolCall] = []
        var pendingSystemMessages: [MessageItem] = []

        for ordered in orderedSources {
            switch ordered.source {
            case .message(let message):
                if message.role == .system {
                    pendingSystemMessages.append(message)
                    continue
                }

                if message.role == .user {
                    if !toolCallBuffer.isEmpty {
                        appendBufferedToolCalls(toolCallBuffer, into: &items)
                        turnToolCalls.append(contentsOf: toolCallBuffer)
                        toolCallBuffer.removeAll(keepingCapacity: true)
                    }

                    if !turnToolCalls.isEmpty {
                        items.append(.turnSummary(makeTurnSummary(from: turnToolCalls)))
                        turnToolCalls.removeAll(keepingCapacity: true)
                    }

                    for systemMessage in pendingSystemMessages {
                        items.append(.message(systemMessage))
                    }
                    pendingSystemMessages.removeAll(keepingCapacity: true)
                }

                if message.role == .agent && !toolCallBuffer.isEmpty {
                    appendBufferedToolCalls(toolCallBuffer, into: &items)
                    turnToolCalls.append(contentsOf: toolCallBuffer)
                    toolCallBuffer.removeAll(keepingCapacity: true)
                }

                items.append(.message(message))

            case .toolCall(let toolCall):
                toolCallBuffer.append(toolCall)
            }
        }

        if !toolCallBuffer.isEmpty {
            turnToolCalls.append(contentsOf: toolCallBuffer)
            if isStreaming {
                appendStreamingToolCallItems(from: toolCallBuffer, into: &items)
            } else {
                appendBufferedToolCalls(toolCallBuffer, into: &items)
                items.append(.turnSummary(makeTurnSummary(from: turnToolCalls)))
                for systemMessage in pendingSystemMessages {
                    items.append(.message(systemMessage))
                }
                pendingSystemMessages.removeAll(keepingCapacity: true)
            }
        } else if !isStreaming && !turnToolCalls.isEmpty {
            items.append(.turnSummary(makeTurnSummary(from: turnToolCalls)))
            for systemMessage in pendingSystemMessages {
                items.append(.message(systemMessage))
            }
            pendingSystemMessages.removeAll(keepingCapacity: true)
        }

        if !pendingSystemMessages.isEmpty {
            for systemMessage in pendingSystemMessages {
                items.append(.message(systemMessage))
            }
        }

        return items
    }

    private func orderedTimelineSources() -> [OrderedTimelineItem] {
        let anchoredTimestamps = anchoredToolCallTimestamps()
        var sequence = 0
        var items: [OrderedTimelineItem] = []
        items.reserveCapacity(messages.count + topLevelToolCalls.count)

        for message in messages {
            let source = OrderedTimelineSource.message(message)
            items.append(
                OrderedTimelineItem(
                    source: source,
                    timestamp: message.timestamp,
                    priority: sortPriority(for: source),
                    sequence: sequence
                )
            )
            sequence += 1
        }

        for toolCall in topLevelToolCalls {
            let source = OrderedTimelineSource.toolCall(toolCall)
            items.append(
                OrderedTimelineItem(
                    source: source,
                    timestamp: anchoredTimestamps[toolCall.id] ?? toolCall.timestamp,
                    priority: sortPriority(for: source),
                    sequence: sequence
                )
            )
            sequence += 1
        }

        items.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.sequence < rhs.sequence
        }

        return items
    }

    private func anchoredToolCallTimestamps() -> [String: Date] {
        var anchoredByID: [String: Date] = [:]

        for message in messages {
            let messageToolCalls = message.toolCalls.filter { $0.parentToolCallId == nil }
            guard !messageToolCalls.isEmpty else { continue }

            for (index, toolCall) in messageToolCalls.enumerated() {
                let remaining = messageToolCalls.count - index
                let anchored = message.timestamp.addingTimeInterval(-Double(remaining) * 0.000_001)
                if let existing = anchoredByID[toolCall.id] {
                    if anchored < existing {
                        anchoredByID[toolCall.id] = anchored
                    }
                } else {
                    anchoredByID[toolCall.id] = anchored
                }
            }
        }

        return anchoredByID
    }

    private func sortPriority(for source: OrderedTimelineSource) -> Int {
        switch source {
        case .toolCall:
            return 1
        case .message(let message):
            switch message.role {
            case .user:
                return 0
            case .agent:
                return 2
            case .system:
                return 3
            }
        }
    }

    private func appendBufferedToolCalls(_ toolCalls: [ToolCall], into items: inout [TimelineSourceItem]) {
        guard !toolCalls.isEmpty else { return }

        if toolCalls.count == 1, let toolCall = toolCalls.first {
            items.append(.toolCall(toolCall))
            return
        }

        items.append(.toolCallGroup(makeToolCallGroup(from: toolCalls)))
    }

    private func appendStreamingToolCallItems(from toolCalls: [ToolCall], into items: inout [TimelineSourceItem]) {
        var explorationBuffer: [ToolCall] = []

        func flushExplorationBuffer() {
            guard !explorationBuffer.isEmpty else { return }
            items.append(.toolCallGroup(makeToolCallGroup(from: explorationBuffer)))
            explorationBuffer.removeAll(keepingCapacity: true)
        }

        for toolCall in toolCalls {
            if isExplorationCandidate(toolCall) {
                explorationBuffer.append(toolCall)
                continue
            }

            flushExplorationBuffer()
            items.append(.toolCall(toolCall))
        }

        flushExplorationBuffer()
    }

    private func makeToolCallGroup(from toolCalls: [ToolCall]) -> ToolCallGroup {
        ToolCallGroup(toolCalls: toolCalls)
    }

    private func makeTurnSummary(from toolCalls: [ToolCall]) -> TurnSummary {
        let timestamps = toolCalls.map(\.timestamp)
        let start = timestamps.min() ?? Date()
        let end = timestamps.max() ?? Date()
        let duration = end.timeIntervalSince(start)
        let key = toolCalls.map(\.id).joined(separator: "|")
        let id = key.isEmpty ? UUID().uuidString : key

        return TurnSummary(
            id: id,
            timestamp: end,
            duration: duration,
            toolCallCount: toolCalls.count,
            fileChanges: turnSummaryFileChanges(from: toolCalls)
        )
    }

    private func turnSummaryFileChanges(from toolCalls: [ToolCall]) -> [FileChangeSummary] {
        var changes: [String: FileChangeSummary] = [:]

        for toolCall in toolCalls where toolCall.kind == .some(.edit) {
            let filePath: String?
            if let path = toolCall.locations?.first?.path {
                filePath = path
            } else if !toolCall.title.isEmpty && toolCall.title.contains("/") {
                filePath = toolCall.title
            } else {
                filePath = nil
            }

            guard let filePath else { continue }

            var linesAdded = 0
            var linesRemoved = 0
            var isNewFile = false

            for content in toolCall.content {
                guard case .diff(let diff) = content else { continue }

                isNewFile = diff.oldText == nil || diff.oldText?.isEmpty == true
                let delta = diffLineDelta(oldText: diff.oldText, newText: diff.newText)
                linesAdded += delta.added
                linesRemoved += delta.removed
            }

            if let existing = changes[filePath] {
                changes[filePath] = FileChangeSummary(
                    path: filePath,
                    isNew: existing.isNew || isNewFile,
                    linesAdded: existing.linesAdded + linesAdded,
                    linesRemoved: existing.linesRemoved + linesRemoved
                )
            } else {
                changes[filePath] = FileChangeSummary(
                    path: filePath,
                    isNew: isNewFile,
                    linesAdded: linesAdded,
                    linesRemoved: linesRemoved
                )
            }
        }

        return changes.values.sorted { $0.path < $1.path }
    }

    private func isExplorationCandidate(_ toolCall: ToolCall) -> Bool {
        if let kind = toolCall.kind {
            let rawValue = kind.rawValue.lowercased()
            if rawValue == "read" || rawValue == "search" || rawValue == "grep" || rawValue == "list" {
                return true
            }
            if kind == .execute && hasListIntent(toolCall) {
                return true
            }
        }

        return hasListIntent(toolCall)
    }

    private func hasListIntent(_ toolCall: ToolCall) -> Bool {
        let normalizedTitle = toolCall.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedTitle.hasPrefix("list ") || normalizedTitle == "list" {
            return true
        }

        if let rawInput = toolCall.rawInput?.value as? [String: Any] {
            if let command = rawInput["command"] as? String, isListCommand(command) {
                return true
            }
            if let cmd = rawInput["cmd"] as? String, isListCommand(cmd) {
                return true
            }
            if let args = rawInput["args"] as? [String], isListCommand(args.joined(separator: " ")) {
                return true
            }
        }

        return false
    }

    private func isListCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }

        let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if ["ls", "find", "fd", "tree", "dir", "rg", "ripgrep", "grep", "glob"].contains(firstToken) {
            return true
        }

        return trimmed.contains(" --files") || trimmed.hasPrefix("list ")
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

    private func makeEntries(from item: TimelineSourceItem, startsAssistantLane: Bool) -> [VVChatTimelineEntry] {
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

    private func messageRevisionToken(_ message: MessageItem) -> Int {
        let suffix = String(message.content.suffix(96))
        return revisionKey("\(message.id)|\(message.role)|\(message.isComplete)|\(message.content.count)|\(suffix)|\(message.contentBlocks.count)")
    }

    private func toolCallRevisionToken(_ call: ToolCall) -> Int {
        let location = call.locations?.first?.path ?? ""
        let contentSignature = call.content.map(toolCallContentSignature).joined(separator: "|")
        return revisionKey(
            "\(call.id)|\(call.kind?.rawValue ?? "nil")|\(call.status.rawValue)|\(call.title)|\(location)|\(contentSignature)"
        )
    }

    private func toolCallContentSignature(_ content: ToolCallContent) -> String {
        switch content {
        case .content(let block):
            switch block {
            case .text(let text):
                return "text:\(text.text.count)"
            case .image(let image):
                return "image:\(image.mimeType):\(image.data.count)"
            case .audio(let audio):
                return "audio:\(audio.mimeType):\(audio.data.count)"
            case .resource(let resource):
                return "resource:\(resource.resource.uri ?? ""):\(resource.resource.mimeType ?? "")"
            case .resourceLink(let link):
                return "link:\(link.name):\(link.uri)"
            }
        case .diff(let diff):
            return "diff:\(diff.path):\(diff.oldText?.count ?? 0):\(diff.newText.count)"
        case .terminal(let terminal):
            return "terminal:\(terminal.terminalId)"
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "<1s"
        }
        if duration < 60 {
            return "\(Int(duration))s"
        }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
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
            let showsCopyAction = latestCopyableAgentMessageID == message.id
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
                timestampSuffixIconURL: showsCopyAction ? copySuffixIconURL(for: message.id) : nil,
                timestampIconSize: max(13, CGFloat(markdownFontSize) - 1),
                timestampIconSpacing: 0
            )
        case .system:
            return nil
        }
    }

    private func presentationRevisionToken(for message: MessageItem, startsAssistantLane: Bool) -> String {
        switch message.role {
        case .user:
            return "user-v4"
        case .agent:
            let copyToken = latestCopyableAgentMessageID == message.id
                ? copyFooterStateToken(for: message.id)
                : "hidden"
            return "assistant-lane-\(startsAssistantLane ? "start" : "cont")-copy-\(copyToken)-v5"
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

    private func toolCallDiffDelta(_ diff: ToolCallDiff) -> (added: Int, removed: Int) {
        diffLineDelta(oldText: diff.oldText, newText: diff.newText)
    }

    private func inlineDiffEntries(for toolCall: ToolCall, entryIDPrefix: String) -> [VVChatTimelineEntry] {
        let diffs = toolDiffContents(for: toolCall)
        guard !diffs.isEmpty else { return [] }

        return diffs.enumerated().map { index, diff in
            let unifiedDiff = inlineDiffPreviewDocument(for: diff)
            let payload = TimelineCustomPayload(
                title: nil,
                body: unifiedDiff,
                status: toolCall.status.rawValue,
                toolKind: toolCall.kind?.rawValue,
                showsAgentLaneIcon: false
            )
            return .custom(
                VVCustomTimelineEntry(
                    id: "\(entryIDPrefix)::diff::\(index)",
                    kind: "toolCallInlineDiff",
                    payload: encodeCustomPayload(payload, fallback: unifiedDiff),
                    revision: revisionKey(unifiedDiff + diff.path + "\(index)" + toolCall.status.rawValue),
                    timestamp: toolCall.timestamp
                )
            )
        }
    }

    private func diffLineDelta(oldText: String?, newText: String) -> (added: Int, removed: Int) {
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

    private func summaryPayloadCard(_ summary: TurnSummary) -> PayloadSummaryCard {
        let rows = summary.fileChanges.map { change in
            let filePath = resolveSummaryFilePath(change.path)
            return PayloadSummaryRow(
                id: change.id,
                title: compactDisplayPath(change.path),
                subtitle: nil,
                iconURL: summaryFileIconURL(path: change.path),
                actionURL: fileOpenURLString(path: filePath),
                additionsText: "+\(change.linesAdded)",
                deletionsText: "-\(change.linesRemoved)"
            )
        }

        let subtitle: String
        if rows.isEmpty {
            subtitle = "\(summary.toolCallCount) tool call\(summary.toolCallCount == 1 ? "" : "s") • \(summary.formattedDuration) • no files modified"
        } else {
            subtitle = "\(summary.toolCallCount) tool call\(summary.toolCallCount == 1 ? "" : "s") • \(summary.formattedDuration)"
        }

        return PayloadSummaryCard(
            title: "Turn Summary",
            subtitle: subtitle,
            rows: rows
        )
    }

    private func makeSummaryCard(from payload: PayloadSummaryCard) -> VVChatSummaryCard {
        let rows = payload.rows.map { row in
            VVChatSummaryCardRow(
                id: row.id,
                title: row.title,
                subtitle: row.subtitle,
                iconURL: row.iconURL,
                actionURL: row.actionURL,
                titleColor: summaryRowTitleColor,
                subtitleColor: summaryRowSubtitleColor,
                additionsText: row.additionsText,
                additionsColor: summaryAdditionsColor,
                deletionsText: row.deletionsText,
                deletionsColor: summaryDeletionsColor,
                hoverFillColor: summaryRowHoverColor
            )
        }

        return VVChatSummaryCard(
            title: payload.title,
            iconURL: symbolIconURL(
                "checklist",
                fallbackID: "turn-summary",
                tintColor: headerIconTintColor,
                pointSize: 12
            ),
            subtitle: payload.subtitle,
            rows: rows,
            titleColor: summaryTitleColor,
            subtitleColor: summarySubtitleColor,
            dividerColor: summaryDividerColor,
            rowDividerColor: summaryRowDividerColor
        )
    }

    private var summaryTitleColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.textColor)
        }
        return colorScheme == .dark ? .rgba(0.96, 0.97, 0.99, 1) : .rgba(0.12, 0.14, 0.18, 1)
    }

    private var summarySubtitleColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.textColor).withOpacity(0.74)
        }
        return colorScheme == .dark ? .rgba(0.83, 0.85, 0.90, 0.92) : .rgba(0.34, 0.38, 0.46, 0.92)
    }

    private var summaryDividerColor: SIMD4<Float> {
        simdColor(from: GhosttyThemeParser.loadDividerColor(named: effectiveTerminalThemeName)).withOpacity(colorScheme == .dark ? 0.9 : 0.7)
    }

    private var summaryRowDividerColor: SIMD4<Float> {
        summaryDividerColor.withOpacity(colorScheme == .dark ? 0.45 : 0.35)
    }

    private var summaryRowTitleColor: SIMD4<Float> {
        summaryTitleColor.withOpacity(0.96)
    }

    private var summaryRowSubtitleColor: SIMD4<Float> {
        summarySubtitleColor.withOpacity(0.9)
    }

    private var summaryAdditionsColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.gitAddedColor)
        }
        return colorScheme == .dark ? .rgba(0.50, 0.86, 0.62, 1) : .rgba(0.11, 0.60, 0.25, 1)
    }

    private var summaryDeletionsColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.gitDeletedColor)
        }
        return colorScheme == .dark ? .rgba(0.94, 0.69, 0.48, 1) : .rgba(0.78, 0.36, 0.08, 1)
    }

    private var summaryRowHoverColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.currentLineColor).withOpacity(colorScheme == .dark ? 0.18 : 0.10)
        }
        return colorScheme == .dark ? .rgba(0.86, 0.90, 0.98, 0.035) : .rgba(0.14, 0.20, 0.30, 0.03)
    }

    private func summaryFileIconURL(path: String) -> String? {
        let iconPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconName = FileIconMapper.iconName(for: iconPath) ?? "file_default"
        guard let image = NSImage(named: iconName),
              let data = image.tiffRepresentation else {
            return nil
        }
        let cacheKey = "turn-summary-file-\(iconName)-\(revisionKey(iconPath))"
        return ChatTimelineHeaderIconStore.urlString(
            for: .customImage(data),
            fallbackAgentId: cacheKey,
            tintColor: nil,
            targetPointSize: 16,
            backingScale: timelineBackingScale
        )
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
        lastBuildMetadata.groupEntryIDs.contains(entryID)
    }

    private func resolveSummaryFilePath(_ rawPath: String) -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        if let worktreePath, !worktreePath.isEmpty {
            return URL(fileURLWithPath: worktreePath)
                .appendingPathComponent(expanded)
                .standardizedFileURL
                .path
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
            .standardizedFileURL
            .path
    }

    private func fileOpenURLString(path: String) -> String {
        var components = URLComponents()
        components.scheme = "aizen-file"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url?.absoluteString ?? path
    }

    private func destinationPath(from url: URL) -> String? {
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

    private func unifiedDiffDocument(for diff: ToolCallDiff) -> String {
        diffDocument(for: diff, contextLines: 3, maxOutputLines: 8_000)
    }

    private func inlineDiffPreviewDocument(for diff: ToolCallDiff) -> String {
        diffDocument(for: diff, contextLines: 2, maxOutputLines: 16)
    }

    private func diffDocument(for diff: ToolCallDiff, contextLines: Int, maxOutputLines: Int) -> String {
        let normalizedPath = normalizedDiffPath(diff.path)
        let oldText = diff.oldText ?? ""
        let oldLines = oldText.isEmpty ? [String]() : oldText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = diff.newText.isEmpty ? [String]() : diff.newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let linePairs = unifiedDiffLines(
            oldLines: oldLines,
            newLines: newLines,
            contextLines: contextLines,
            maxOutputLines: maxOutputLines
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
        return VVChatMessagePresentation(
            timestampPrefixIconURL: timestampClockIconURL(),
            timestampSuffixIconURL: nil,
            timestampIconSize: timestampSymbolSize,
            timestampIconSpacing: 6
        )
    }

    private func hasCopyableMessageContent(_ message: MessageItem) -> Bool {
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return true
        }

        let markdown = messageMarkdown(message).trimmingCharacters(in: .whitespacesAndNewlines)
        return !markdown.isEmpty
    }

    private var timestampSymbolSize: CGFloat {
        max(14, CGFloat(markdownFontSize) - 0.5)
    }

    private func timestampClockIconURL() -> String? {
        symbolIconURL(
            "clock",
            fallbackID: "timestamp-clock",
            tintColor: timestampIconTintColor
        )
    }

    private func copySuffixIconURL(for messageID: String) -> String? {
        let isActive = copiedUserMessageID == messageID
        let symbolName: String
        let tintColor: NSColor

        if isActive {
            switch copiedUserMessageState {
            case .idle:
                symbolName = "doc.on.doc"
                tintColor = copyIconIdleTintColor
            case .transition:
                symbolName = "ellipsis"
                tintColor = copyIconHoverTintColor
            case .confirmed:
                symbolName = "checkmark"
                tintColor = copyIconConfirmedTintColor
            }
        } else {
            symbolName = "doc.on.doc"
            tintColor = copyIconIdleTintColor
        }

        return symbolIconURL(
            symbolName,
            fallbackID: "copy-\(symbolName)-\(copyFooterStateToken(for: messageID))",
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
            if let markdown = attachmentMarkdown(for: block, role: message.role) {
                lines.append(markdown)
            }
        }

        return normalizedMessageMarkdown(lines.joined(separator: "\n\n"), role: message.role)
    }

    private func attachmentMarkdown(for block: ContentBlock, role: MessageRole) -> String? {
        switch block {
        case .text(let text):
            let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : normalizedMessageMarkdown(text.text, role: role)
        case .image:
            return escapeMarkdownForPlainText("[Image attachment]")
        case .audio:
            return escapeMarkdownForPlainText("[Audio attachment]")
        case .resource(let resource):
            if role == .user {
                let label = resourceLabel(from: resource.resource.uri, fallback: "Resource attachment")
                return escapeMarkdownForPlainText(label)
            }
            if let uri = resource.resource.uri {
                return "[Resource](\(uri))"
            }
            return "[Resource attachment]"
        case .resourceLink(let link):
            if role == .user {
                return escapeMarkdownForPlainText(link.name)
            }
            return "[\(link.name)](\(link.uri))"
        }
    }

    private func resourceLabel(from rawURI: String?, fallback: String) -> String {
        guard let rawURI, !rawURI.isEmpty else { return fallback }
        if let url = URL(string: rawURI) {
            let component = url.lastPathComponent
            if !component.isEmpty {
                return component
            }
        }
        let trimmed = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedMessageMarkdown(_ content: String, role: MessageRole) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if role == .user {
            return escapeMarkdownForPlainText(trimmed)
        }

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

    private func escapeMarkdownForPlainText(_ content: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(content.count)

        let specialCharacters: Set<Character> = ["\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "!", "|", ">"]

        for character in content {
            if specialCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }

        return escaped
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

    private func toolCallHeaderTitle(_ toolCall: ToolCall) -> String {
        let base: String
        switch toolCall.kind {
        case .read:
            base = "Read"
        case .edit:
            base = "Edited"
        case .delete:
            base = "Deleted"
        case .move:
            base = "Moved"
        case .search:
            base = toolCallSearchHeaderTitle(toolCall) ?? "Searched"
        case .execute:
            if toolCallRawCommand(toolCall) != nil {
                base = "Ran"
            } else {
                base = toolCallInputPreview(toolCall) ?? sanitizedToolTitle(toolCall.title) ?? "Ran"
            }
        case .think:
            base = "Thought"
        case .fetch:
            base = "Fetched"
        case .switchMode:
            base = "Switched"
        case .plan:
            base = "Planned"
        case .exitPlanMode:
            base = "Exited plan"
        case .other:
            base = humanizedToolTitleAction(toolCall.title) ?? sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        case nil:
            base = humanizedToolTitleAction(toolCall.title) ?? sanitizedToolTitle(toolCall.title) ?? "Ran a tool"
        }

        switch toolCall.status.rawValue {
        case "in_progress":
            return "\(base)…"
        default:
            return base
        }
    }

    private func toolCallHeaderBadges(_ toolCall: ToolCall) -> [VVHeaderBadge]? {
        var badges: [VVHeaderBadge] = []

        if let path = toolCallHeaderPath(toolCall) {
            badges.append(VVHeaderBadge(text: path, color: toolCallPathBadgeColor))
        }

        if toolCall.kind == .execute,
           let command = toolCallCommandBadgeText(toolCall) {
            badges.append(VVHeaderBadge(text: command, color: toolCallPathBadgeColor))
        }

        if let delta = toolCallAggregateDelta(toolCall) {
            let green: SIMD4<Float> = colorScheme == .dark
                ? .rgba(0.42, 0.82, 0.52, 1)
                : .rgba(0.14, 0.64, 0.24, 1)
            let red: SIMD4<Float> = colorScheme == .dark
                ? .rgba(0.92, 0.42, 0.44, 1)
                : .rgba(0.82, 0.24, 0.28, 1)
            badges.append(VVHeaderBadge(text: "+\(delta.added)", color: green))
            badges.append(VVHeaderBadge(text: "-\(delta.removed)", color: red))
            if delta.fileCount > 1 {
                let dimmed: SIMD4<Float> = colorScheme == .dark
                    ? .rgba(0.7, 0.7, 0.7, 0.6)
                    : .rgba(0.3, 0.3, 0.3, 0.6)
                badges.append(VVHeaderBadge(text: "\(delta.fileCount) files", color: dimmed))
            }
        } else if toolCall.kind != .edit,
                  let outcome = toolCallCompactOutcome(toolCall),
                  !toolCallHeaderTitle(toolCall).localizedCaseInsensitiveContains(outcome) {
            badges.append(VVHeaderBadge(text: outcome, color: toolCallPathBadgeColor))
        }

        return badges.isEmpty ? nil : badges
    }

    private func toolCallHeaderPath(_ toolCall: ToolCall) -> String? {
        guard let path = primaryPath(for: toolCall) else { return nil }
        return compactDisplayPath(path)
    }

    private var toolCallPathBadgeColor: SIMD4<Float> {
        colorScheme == .dark ? .rgba(0.72, 0.74, 0.79, 0.72) : .rgba(0.38, 0.42, 0.50, 0.78)
    }

    private func toolCallDetailMarkdown(_ toolCall: ToolCall) -> String {
        toolCallSummaryBody(toolCall)
    }

    private func toolCallSummaryBody(_ toolCall: ToolCall) -> String {
        switch toolCall.kind {
        case .fetch:
            return fetchToolSummary(toolCall)
        case .think:
            if let text = firstTextContent(for: toolCall) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return abbreviated(trimmed, maxLength: 240)
                }
            }
            return ""
        case .execute:
            if let text = firstTextContent(for: toolCall) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return truncatedOutputBlock(trimmed, maxLines: 6)
                }
            }
            return ""
        case .read:
            return ""
        case .search:
            if let text = firstTextContent(for: toolCall) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return truncatedOutputBlock(trimmed, maxLines: 6)
                }
            }
            return ""
        case .edit, .delete, .move:
            return ""
        case .switchMode, .plan, .exitPlanMode:
            return ""
        case .other, nil:
            return genericToolSummary(toolCall)
        }
    }

    private func fetchToolSummary(_ toolCall: ToolCall) -> String {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else {
            return firstTextContentPreview(toolCall, maxLines: 4)
        }
        if let url = nestedInputString(in: raw, preferredKeys: ["url", "uri", "href", "endpoint"]) {
            let display = abbreviated(url, maxLength: 120)
            let output = firstTextContentPreview(toolCall, maxLines: 4)
            if output.isEmpty {
                return display
            }
            return display + "\n\n" + output
        }
        return firstTextContentPreview(toolCall, maxLines: 4)
    }

    private func genericToolSummary(_ toolCall: ToolCall) -> String {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else {
            return firstTextContentPreview(toolCall, maxLines: 4)
        }

        if let query = nestedInputString(in: raw, preferredKeys: ["query", "pattern", "search", "prompt", "question"]) {
            let display = abbreviated(query, maxLength: 160)
            let output = firstTextContentPreview(toolCall, maxLines: 4)
            if output.isEmpty {
                return display
            }
            return display + "\n\n" + output
        }

        if let url = nestedInputString(in: raw, preferredKeys: ["url", "uri", "href"]) {
            let display = abbreviated(url, maxLength: 120)
            let output = firstTextContentPreview(toolCall, maxLines: 4)
            if output.isEmpty {
                return display
            }
            return display + "\n\n" + output
        }

        if let path = nestedInputString(in: raw, preferredKeys: ["path", "file", "filePath"]) {
            return compactDisplayPath(path)
        }

        if let command = nestedInputString(in: raw, preferredKeys: ["command", "cmd"]) {
            return "`" + abbreviated(command, maxLength: 100) + "`"
        }

        return firstTextContentPreview(toolCall, maxLines: 4)
    }

    private func firstTextContentPreview(_ toolCall: ToolCall, maxLines: Int) -> String {
        guard let text = firstTextContent(for: toolCall) else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return truncatedOutputBlock(trimmed, maxLines: maxLines)
    }

    private func truncatedOutputBlock(_ text: String, maxLines: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= maxLines {
            return abbreviated(text, maxLength: maxLines * 120)
        }
        let preview = lines.prefix(maxLines).joined(separator: "\n")
        let remaining = lines.count - maxLines
        return abbreviated(preview, maxLength: maxLines * 120) + "\n… \(remaining) more line\(remaining == 1 ? "" : "s")"
    }

    private func toolCallGroupTitle(_ group: ToolCallGroup) -> String {
        var segments: [String] = [
            toolGroupActionSummary(group)
        ]
        if let duration = group.formattedDuration {
            segments.append(duration)
        }
        return segments.joined(separator: " • ")
    }

    private func toolGroupActionSummary(_ group: ToolCallGroup) -> String {
        var kindCounts: [(label: String, count: Int)] = []
        var counts: [String: Int] = [:]
        // Preserve insertion order
        var orderedLabels: [String] = []

        for call in group.toolCalls {
            let label = toolKindShortLabel(call.kind)
            counts[label, default: 0] += 1
            if !orderedLabels.contains(label) {
                orderedLabels.append(label)
            }
        }

        for label in orderedLabels {
            kindCounts.append((label: label, count: counts[label]!))
        }

        if kindCounts.count == 1 {
            let item = kindCounts[0]
            return "\(item.label) \(item.count) file\(item.count == 1 ? "" : "s")"
        }

        return kindCounts.map { "\($0.label) \($0.count)" }.joined(separator: ", ")
    }

    private func toolKindShortLabel(_ kind: ToolKind?) -> String {
        switch kind {
        case .read: return "Read"
        case .edit: return "Edited"
        case .delete: return "Deleted"
        case .move: return "Moved"
        case .search: return "Searched"
        case .execute: return "Ran"
        case .think: return "Thought"
        case .fetch: return "Fetched"
        case .plan: return "Planned"
        case .switchMode: return "Switched"
        case .exitPlanMode: return "Exited plan"
        case .other, nil: return "Ran"
        }
    }

    private func toolCallGroupMarkdown(_ group: ToolCallGroup, isExpanded: Bool) -> String {
        guard !isExpanded else { return "" }
        var lines: [String] = []
        for call in group.toolCalls.prefix(8) {
            let action = toolCallHumanAction(call)
            lines.append("- \(action)")
        }
        if group.toolCalls.count > 8 {
            lines.append("- … \(group.toolCalls.count - 8) more")
        }
        return lines.joined(separator: "\n")
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

        if let command = toolCallRawCommand(toolCall) {
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

    private func toolCallSearchHeaderTitle(_ toolCall: ToolCall) -> String? {
        if let input = toolCallInputPreview(toolCall) {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.lowercased().hasPrefix("searched ") {
                return abbreviated(trimmed, maxLength: 96)
            }
            return "Searched \(abbreviated(trimmed, maxLength: 88))"
        }

        if let action = humanizedToolTitleAction(toolCall.title) {
            let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.lowercased().hasPrefix("searched ") {
                return abbreviated(trimmed, maxLength: 96)
            }
        }

        return nil
    }

    private func toolCallCommandBadgeText(_ toolCall: ToolCall) -> String? {
        guard let command = toolCallRawCommand(toolCall) else { return nil }
        return abbreviated(singleLineBadgeText(command), maxLength: 88)
    }

    private func toolCallRawCommand(_ toolCall: ToolCall) -> String? {
        guard let raw = toolCall.rawInput?.value as? [String: Any] else { return nil }
        return nestedCommandString(
            in: raw,
            preferredKeys: ["command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"]
        )
    }

    private func singleLineBadgeText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    private func nestedCommandString(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = recursiveCommandValue(dict[key], preferredKey: key) {
                return value
            }
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

    private func recursiveCommandValue(_ value: Any?, preferredKey: String, depth: Int = 0) -> String? {
        guard depth < 8, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let strings = value as? [String] {
            let cleaned = strings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned.joined(separator: " ")
        }

        if let dict = value as? [String: Any] {
            if let nested = recursiveCommandValue(dict[preferredKey], preferredKey: preferredKey, depth: depth + 1) {
                return nested
            }
            for fallback in ["value", "text", "command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"] {
                if let nested = recursiveCommandValue(dict[fallback], preferredKey: preferredKey, depth: depth + 1) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            let strings = array.compactMap { item -> String? in
                guard let string = item as? String else { return nil }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !strings.isEmpty {
                return strings.joined(separator: " ")
            }
            for item in array {
                if let nested = recursiveCommandValue(item, preferredKey: preferredKey, depth: depth + 1) {
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
            return abbreviated(command, maxLength: 120)
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

    private struct PayloadBadge: Codable {
        var text: String
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    private struct PayloadSummaryRow: Codable {
        var id: String
        var title: String
        var subtitle: String?
        var iconURL: String?
        var actionURL: String?
        var additionsText: String?
        var deletionsText: String?
    }

    private struct PayloadSummaryCard: Codable {
        var title: String
        var subtitle: String?
        var rows: [PayloadSummaryRow]
    }

    private struct TimelineCustomPayload: Codable {
        var title: String?
        var body: String
        var status: String?
        var toolKind: String?
        var showsAgentLaneIcon: Bool?
        var badges: [PayloadBadge]?
        var summaryCard: PayloadSummaryCard?
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

    private func toolGroupStatusNSColor(statusRawValue: String?) -> NSColor {
        switch statusRawValue {
        case "failed":
            return colorScheme == .dark
                ? NSColor(red: 0.92, green: 0.42, blue: 0.44, alpha: 1)
                : NSColor(red: 0.82, green: 0.24, blue: 0.28, alpha: 1)
        case "in_progress":
            return colorScheme == .dark
                ? NSColor(red: 0.98, green: 0.78, blue: 0.36, alpha: 1)
                : NSColor(red: 0.88, green: 0.62, blue: 0.06, alpha: 1)
        default:
            // Completed — use normal tint color at full opacity
            return headerIconTintColor
        }
    }

    private var dimmedMetaOpacity: Float {
        colorScheme == .dark ? 0.40 : 0.50
    }

    private func revisionKey(_ value: String) -> Int {
        let hashed = value.hashValue
        if hashed == Int.min {
            return Int.max
        }
        return abs(hashed)
    }
}

private enum CopyFooterState {
    case idle
    case transition
    case confirmed
}
