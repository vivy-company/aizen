//
//  ChatMessageList+TimelineSync.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import Foundation
import VVChatTimeline

extension ChatMessageList {
    func apply(entries newEntries: [VVChatTimelineEntry], scrollToBottom: Bool) {
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

    func reportTimelineStateIfNeeded(_ state: VVChatTimelineState) {
        guard lastReportedTimelineState != state else { return }
        lastReportedTimelineState = state
        onTimelineStateChange(state)
    }
}
