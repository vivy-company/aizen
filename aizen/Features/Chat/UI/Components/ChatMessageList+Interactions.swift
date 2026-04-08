//
//  ChatMessageList+Interactions.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import AppKit
import Foundation
import VVChatTimeline

extension ChatMessageList {
    func handleEntryActivate(_ entryID: String) {
        if isToolGroupEntryID(entryID) {
            toggleToolGroupEntry(entryID)
            return
        }
    }

    func toggleToolGroupEntry(_ entryID: String) {
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

    func handleTimelineLinkActivate(_ rawLink: String) {
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

    func handleUserMessageCopyHoverChange(_ messageID: String?) {
        guard hoveredCopyUserMessageID != messageID else { return }
        hoveredCopyUserMessageID = messageID
    }

    func toolCallGroup(forEntryID entryID: String) -> ToolCallGroup? {
        for item in assembleTimelineSourceItems() {
            guard case .toolCallGroup(let group) = item, group.entryID == entryID else { continue }
            return group
        }
        return nil
    }

    func toolCallGroupEntryRange(
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
}
