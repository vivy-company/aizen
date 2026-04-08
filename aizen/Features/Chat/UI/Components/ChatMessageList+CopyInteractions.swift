//
//  ChatMessageList+CopyInteractions.swift
//  aizen
//

import Foundation

extension ChatMessageList {
    func handleUserMessageCopyAction(_ messageID: String) {
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

    func timelineMessage(withID messageID: String) -> MessageItem? {
        lastBuildMetadata.messagesByID[messageID]
    }
}
