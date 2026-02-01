//
//  MessageBubbleView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import SwiftUI

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: MessageItem
    let agentName: String?

    @State private var showCopyConfirmation = false

    private var alignment: HorizontalAlignment {
        switch message.role {
        case .user:
            return .trailing
        case .agent:
            return .leading
        case .system:
            return .center
        }
    }

    private var bubbleAlignment: Alignment {
        switch message.role {
        case .user:
            return .trailing
        case .agent:
            return .leading
        case .system:
            return .center
        }
    }

    private var agentAttachmentBlocks: [ContentBlock] {
        message.contentBlocks.filter { block in
            switch block {
            case .text:
                return false
            case .image, .audio, .resource, .resourceLink:
                return true
            }
        }
    }

    private var shouldShowAgentMessage: Bool {
        guard message.role == .agent else { return true }
        let hasContent = !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasContent || !agentAttachmentBlocks.isEmpty
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            if message.role == .agent, let identifier = agentName, shouldShowAgentMessage {
                HStack(spacing: 4) {
                    AgentIconView(agent: identifier, size: 16)
                    Text(agentDisplayName.capitalized)
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.vertical, 4)
            }

            // User message bubble
            if message.role == .user {
                HStack {
                    Spacer(minLength: 60)

                    UserBubble(
                        content: message.content,
                        timestamp: message.timestamp,
                        contentBlocks: message.contentBlocks,
                        showCopyConfirmation: showCopyConfirmation,
                        copyAction: copyMessage,
                        backgroundView: { backgroundView }
                    )
                }
            }

            // Agent message - hide if content is empty and message is complete
            else if message.role == .agent {
                if shouldShowAgentMessage {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                MessageContentView(content: message.content, isStreaming: !message.isComplete)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !agentAttachmentBlocks.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(agentAttachmentBlocks.enumerated()), id: \.offset) { _, block in
                                        ContentBlockRenderer(block: block, style: .full)
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                Text(formatTimestamp(message.timestamp))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)

                                if let executionTime = message.executionTime {
                                    Text(DurationFormatter.short(executionTime))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        Spacer(minLength: 60)
                    }
                }
                // Empty agent message - render nothing
            }

            // System message
            else if message.role == .system {
                Text(message.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: bubbleAlignment)
        .transition(message.role == .agent && !message.isComplete ? .identity : .asymmetric(
            insertion: .scale(scale: 0.95, anchor: bubbleAlignment == .trailing ? .bottomTrailing : .bottomLeading)
                .combined(with: .opacity),
            removal: .opacity
        ))
        .animation(message.isComplete ? .spring(response: 0.4, dampingFraction: 0.8) : nil, value: message.isComplete)
    }

    private var agentDisplayName: String {
        guard let agentName else { return "" }
        if let meta = AgentRegistry.shared.getMetadata(for: agentName) {
            return meta.name
        }
        return agentName
    }

    @ViewBuilder
    private var backgroundView: some View {
        Color.clear
            .background(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
            }
    }

    private func copyMessage() {
        Clipboard.copy(message.content)

        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        DateFormatters.shortTime.string(from: date)
    }
}

// MARK: - User Bubble

private struct BubbleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct UserBubble<Background: View>: View {
    let content: String
    let timestamp: Date
    let contentBlocks: [ContentBlock]
    let showCopyConfirmation: Bool
    let copyAction: () -> Void
    @ViewBuilder let backgroundView: () -> Background

    @State private var measuredWidth: CGFloat?
    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize

    private var chatFont: Font {
        chatFontFamily == "System Font" ? .system(size: chatFontSize) : .custom(chatFontFamily, size: chatFontSize)
    }

    private let maxContentWidth: CGFloat = 420
    private let hPadding: CGFloat = 16
    private let vPadding: CGFloat = 12

    /// Attachment blocks are all content blocks except the first .text block (which is the main message)
    private var attachmentBlocks: [ContentBlock] {
        var foundFirstText = false
        return contentBlocks.filter { block in
            switch block {
            case .text:
                if !foundFirstText {
                    foundFirstText = true
                    return false // Skip first text block (main message)
                }
                return true // Additional text blocks are pasted text attachments
            case .image, .resource, .resourceLink:
                return true
            case .audio:
                return false
            }
        }
    }
    
    private var hasAttachments: Bool {
        !attachmentBlocks.isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Text bubble
            bubbleContent
                .padding(.horizontal, hPadding)
                .padding(.vertical, vPadding)
                .frame(width: calculatedBubbleWidth, alignment: .trailing)
                .background(backgroundView())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .background(measureUnwrappedWidth)
                .contextMenu {
                    Button {
                        copyAction()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

            // Attachments outside bubble (pasted text, images, files)
            if hasAttachments {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(Array(attachmentBlocks.enumerated()), id: \.offset) { _, block in
                        attachmentView(for: block)
                    }
                }
            }

            // Footer outside bubble
            HStack(spacing: 8) {
                Text(formatTimestamp(timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Button(action: copyAction) {
                    Image(systemName: showCopyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(showCopyConfirmation ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "chat.message.copy"))
            }
            .padding(.trailing, 4)
        }
    }

    private var bubbleContent: some View {
        Text(content)
            .font(chatFont)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxContentWidth, alignment: .leading)
    }

    @ViewBuilder
    private func attachmentView(for block: ContentBlock) -> some View {
        switch block {
        case .text(let textContent):
            // Pasted text attachment (first .text block is filtered out in attachmentBlocks)
            textAttachmentChip(textContent.text)
        case .image(let imageContent):
            ImageAttachmentCardView(data: imageContent.data)
        case .resource(let resourceContent):
            if let uri = resourceContent.resource.uri {
                UserAttachmentChip(
                    name: URL(string: uri)?.lastPathComponent ?? "File",
                    uri: uri
                )
            }
        case .resourceLink(let linkContent):
            UserAttachmentChip(
                name: linkContent.name,
                uri: linkContent.uri
            )
        case .audio:
            EmptyView()
        }
    }

    private func textAttachmentChip(_ text: String) -> some View {
        let stats = TextAttachmentStats(text: text)
        return AttachmentChip(
            label: AnyView(
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)

                    Text("Pasted Text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(stats.displayInfo)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            ),
            detailView: AnyView(TextAttachmentDetailView(content: text, showsCopyButton: true)),
            style: AttachmentChip.Style(showsDelete: false, showsHoverFade: false)
        )
    }

    private var measureUnwrappedWidth: some View {
        Text(content)
            .font(chatFont)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: BubbleWidthKey.self, value: geo.size.width)
                }
            )
            .hidden()
            .onPreferenceChange(BubbleWidthKey.self) { width in
                measuredWidth = width
            }
    }

    private var calculatedBubbleWidth: CGFloat? {
        guard let measured = measuredWidth else { return nil }
        // Minimum width for timestamp (~50pt) + some padding
        let minContentWidth: CGFloat = 60
        let contentWidth = min(max(measured, minContentWidth), maxContentWidth)
        return contentWidth + hPadding * 2
    }

    private func formatTimestamp(_ date: Date) -> String {
        DateFormatters.shortTime.string(from: date)
    }
}

// MARK: - Agent Badge

struct AgentBadge: View {
    let name: String

    var body: some View {
        PillBadge(
            text: name,
            color: .blue,
            textColor: .white,
            font: .caption,
            fontWeight: .medium,
            horizontalPadding: 8,
            verticalPadding: 4,
            backgroundOpacity: 1
        )
    }
}

// MARK: - Preview

#Preview("User Message") {
    VStack {
        MessageBubbleView(
            message: MessageItem(
                id: "1",
                role: .user,
                content: "How do I implement a neural network in Swift?",
                timestamp: Date()
            ),
            agentName: nil
        )
    }
    .frame(width: 600)
    .padding()
}

#Preview("Agent Message with Code") {
    VStack {
        MessageBubbleView(
            message: MessageItem(
                id: "2",
                role: .agent,
                content: """
                Here's a simple neural network implementation:

                ```swift
                class NeuralNetwork {
                    var weights: [[Double]]

                    init(layers: [Int]) {
                        self.weights = []
                    }
                }
                ```

                This creates the basic structure.
                """,
                timestamp: Date()
            ),
            agentName: "Claude"
        )
    }
    .frame(width: 600)
    .padding()
}

#Preview("System Message") {
    VStack {
        MessageBubbleView(
            message: MessageItem(
                id: "3",
                role: .system,
                content: "Session started with agent in /Users/user/project",
                timestamp: Date()
            ),
            agentName: nil
        )
    }
    .frame(width: 600)
    .padding()
}

#Preview("All Message Types") {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(
                message: MessageItem(
                    id: "1",
                    role: .system,
                    content: "Session started",
                    timestamp: Date().addingTimeInterval(-300)
                ),
                agentName: nil
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "2",
                    role: .user,
                    content: "Can you help me with git?",
                    timestamp: Date().addingTimeInterval(-240)
                ),
                agentName: nil
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "3",
                    role: .agent,
                    content: "I can help with git commands. What do you need?",
                    timestamp: Date().addingTimeInterval(-180)
                ),
                agentName: "Claude"
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "4",
                    role: .user,
                    content: "Show me how to create a branch",
                    timestamp: Date().addingTimeInterval(-120)
                ),
                agentName: nil
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "5",
                    role: .agent,
                    content: """
                    Create a new branch with:

                    ```bash
                    git checkout -b feature/new-feature
                    ```

                    This creates and switches to the new branch.
                    """,
                    timestamp: Date().addingTimeInterval(-60)
                ),
                agentName: "Claude"
            )
        }
        .padding()
    }
    .frame(width: 600, height: 800)
}
