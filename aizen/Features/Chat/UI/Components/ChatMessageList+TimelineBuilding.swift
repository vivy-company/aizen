//
//  ChatMessageList+TimelineBuilding.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation
import SwiftUI
import VVChatTimeline

extension ChatMessageList {
    struct TimelineBuildResult {
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

    func buildTimeline() -> TimelineBuildResult {
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
                    hasRenderedAgentMessageInTurn = message.role == .agent
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
                revision: revisionKey(
                    messageRevisionSeed + "|" + presentationRevisionToken(for: message, startsAssistantLane: startsAssistantLane)
                ),
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
            return buildToolCallGroupEntries(group, startsAssistantLane: startsAssistantLane)

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
}
