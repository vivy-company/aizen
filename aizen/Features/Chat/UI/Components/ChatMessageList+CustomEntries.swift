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
