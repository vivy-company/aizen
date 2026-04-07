import ACP
import Foundation
import SwiftUI
import VVChatTimeline

extension ChatMessageList {
    func buildToolCallGroupEntries(
        _ group: ToolCallGroup,
        startsAssistantLane: Bool
    ) -> [VVChatTimelineEntry] {
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
    }
}
