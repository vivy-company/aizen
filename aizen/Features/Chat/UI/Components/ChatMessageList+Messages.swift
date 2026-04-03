import ACP
import SwiftUI
import VVChatTimeline
import VVMetalPrimitives

extension ChatMessageList {
    var latestCopyableAgentMessageID: String? {
        messages.reversed().first { message in
            guard message.role == .agent else { return false }
            return hasCopyableMessageContent(message)
        }?.id
    }

    func messageRevisionToken(_ message: MessageItem) -> Int {
        let suffix = String(message.content.suffix(96))
        return revisionKey(
            "\(message.id)|\(message.role)|\(message.isComplete)|\(message.content.count)|\(suffix)|\(message.contentBlocks.count)"
        )
    }

    func toolCallRevisionToken(_ call: ToolCall) -> Int {
        let location = call.locations?.first?.path ?? ""
        let contentSignature = call.content.map(toolCallContentSignature).joined(separator: "|")
        return revisionKey(
            "\(call.id)|\(call.kind?.rawValue ?? "nil")|\(call.status.rawValue)|\(call.title)|\(location)|\(contentSignature)"
        )
    }

    func toolCallContentSignature(_ content: ToolCallContent) -> String {
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

    static func formattedDuration(_ duration: TimeInterval) -> String {
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

    func mapRole(_ role: MessageRole) -> VVChatMessageRole {
        switch role {
        case .user:
            return .user
        case .agent:
            return .assistant
        case .system:
            return .system
        }
    }

    func messagePresentation(for message: MessageItem, startsAssistantLane: Bool) -> VVChatMessagePresentation? {
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

    func presentationRevisionToken(for message: MessageItem, startsAssistantLane: Bool) -> String {
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

    func copyFooterStateToken(for messageID: String) -> String {
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

    func hasCopyableMessageContent(_ message: MessageItem) -> Bool {
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return true
        }

        let markdown = messageMarkdown(message).trimmingCharacters(in: .whitespacesAndNewlines)
        return !markdown.isEmpty
    }
}
