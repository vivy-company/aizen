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

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            if message.role == .agent, let identifier = agentName {
                HStack(spacing: 4) {
                    AgentIconView(agent: identifier, size: 16)
                    Text(agentDisplayName.capitalized)
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.vertical, 4)
            }

            HStack {
                if message.role == .user {
                    Spacer(minLength: 100)
                }

                if message.role == .system {
                    Spacer()
                }

                VStack(alignment: message.role == .system ? .center : .leading, spacing: 6) {
                    if message.role == .system {
                        Text(message.content)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    } else {
                        MessageContentView(content: message.content, isStreaming: message.role == .agent && !message.isComplete)
                    }

                    // Only show attachment chips for user messages with non-text attachments
                    if message.role == .user, message.contentBlocks.count > 1 {
                        let attachmentBlocks = message.contentBlocks.dropFirst().filter { block in
                            // Only show non-text blocks as attachments
                            if case .text = block { return false }
                            return true
                        }
                        if !attachmentBlocks.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(attachmentBlocks.indices, id: \.self) { index in
                                    AttachmentChipView(block: attachmentBlocks[index])
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    if message.role != .system {
                        HStack(spacing: 8) {
                            Text(formatTimestamp(message.timestamp))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)

                            if message.role == .agent, let executionTime = message.executionTime {
                                Text(formatExecutionTime(executionTime))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            if message.role == .user {
                                Spacer()

                                Button(action: copyMessage) {
                                    Image(systemName: showCopyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(showCopyConfirmation ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(String(localized: "chat.message.copy"))
                            }
                        }
                    }
                }
                .if(message.role == .user) { view in
                    view
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            backgroundView
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .fixedSize(horizontal: message.role == .system || message.role == .user, vertical: false)
                .frame(maxWidth: message.role == .user ? 500 : .infinity, alignment: bubbleAlignment)

                if message.role == .agent {
                    Spacer(minLength: 100)
                }

                if message.role == .system {
                    Spacer()
                }
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
