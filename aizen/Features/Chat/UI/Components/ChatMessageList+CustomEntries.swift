//
//  ChatMessageList+CustomEntries.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import AppKit
import SwiftUI
import VVCode
import VVChatTimeline
import VVMetalPrimitives

extension ChatMessageList {
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
                    headerIconURL: symbolIconURL(
                        "square.stack.3d.up",
                        fallbackID: "tool-group-\(decoded?.status ?? "default")",
                        tintColor: statusTintColor
                    ),
                    headerTrailingIconURL: symbolIconURL(
                        chevronSymbol,
                        fallbackID: "chevron-\(isGroupExpanded ? "down" : "right")",
                        tintColor: headerIconTintColor
                    ),
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

    func symbolIconURL(
        _ symbolName: String,
        fallbackID: String? = nil,
        tintColor: NSColor? = nil,
        pointSize: CGFloat? = nil
    ) -> String? {
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

    func encodeCustomPayload(_ payload: TimelineCustomPayload, fallback: String) -> Data {
        if let encoded = try? JSONEncoder().encode(payload) {
            return encoded
        }
        return Data(fallback.utf8)
    }
}

extension ChatMessageList {
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
}
