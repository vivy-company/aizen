//
//  ChatMessageList+TimelineSync.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import Foundation
import VVChatTimeline

extension ChatMessageList {
    struct EntryReplacement {
        let id: String
        let oldEntry: VVChatTimelineEntry
        let newEntry: VVChatTimelineEntry
    }

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

    func stableAnchorID(from oldEntries: [VVChatTimelineEntry], to newEntries: [VVChatTimelineEntry]) -> String? {
        let newIDs = Set(newEntries.map(\.id))
        for entry in oldEntries {
            if newIDs.contains(entry.id) {
                return entry.id
            }
        }
        return newEntries.first?.id
    }

    func canApplyIncrementally(from oldEntries: [VVChatTimelineEntry], to newEntries: [VVChatTimelineEntry]) -> Bool {
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

    func append(_ entry: VVChatTimelineEntry) {
        prepareAppendTransition()
        switch entry {
        case .message(let message):
            controller.appendMessage(message)
        case .custom(let custom):
            controller.appendCustomEntry(custom)
        }
    }

    func prepareAppendTransition() {
        let anchorID = controller.entries.last?.id ?? appliedEntries.last?.id
        if let anchorID {
            controller.prepareLayoutTransition(anchorItemID: anchorID)
        }
    }

    func makeEntryReplacements(
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

    func applyEntryReplacements(_ replacements: [EntryReplacement], scrollToBottom: Bool) {
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

    func applyDraftMessageUpdateIfPossible(_ replacement: EntryReplacement) -> Bool {
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

    func reportTimelineStateIfNeeded(_ state: VVChatTimelineState) {
        guard lastReportedTimelineState != state else { return }
        lastReportedTimelineState = state
        onTimelineStateChange(state)
    }
}
