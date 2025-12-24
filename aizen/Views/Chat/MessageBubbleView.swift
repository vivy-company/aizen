//
//  MessageBubbleView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

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

    private var shouldShowAgentMessage: Bool {
        guard message.role == .agent else { return true }
        let hasContent = !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasContent || !message.isComplete
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
                            MessageContentView(content: message.content, isStreaming: !message.isComplete)

                            HStack(spacing: 8) {
                                Text(formatTimestamp(message.timestamp))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)

                                if let executionTime = message.executionTime {
                                    Text(formatExecutionTime(executionTime))
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
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: message.id)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)

        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func formatTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    private func formatExecutionTime(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
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
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxContentWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func attachmentView(for block: ContentBlock) -> some View {
        switch block {
        case .text(let textContent):
            // Pasted text attachment (first .text block is filtered out in attachmentBlocks)
            TextAttachmentChip(text: textContent.text)
        case .image(let imageContent):
            ImageAttachmentCardView(data: imageContent.data, mimeType: imageContent.mimeType)
        case .resource(let resourceContent):
            if let uri = resourceContent.resource.uri {
                UserAttachmentChip(
                    name: URL(string: uri)?.lastPathComponent ?? "File",
                    uri: uri,
                    mimeType: nil
                )
            }
        case .resourceLink(let linkContent):
            UserAttachmentChip(
                name: linkContent.name,
                uri: linkContent.uri,
                mimeType: linkContent.mimeType
            )
        case .audio:
            EmptyView()
        }
    }

    private var measureUnwrappedWidth: some View {
        Text(content)
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
        userBubbleTimestampFormatter.string(from: date)
    }
}

private let userBubbleTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter
}()

// MARK: - Agent Badge

struct AgentBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue)
            .clipShape(Capsule())
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

