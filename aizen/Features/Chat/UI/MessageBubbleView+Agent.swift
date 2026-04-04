import SwiftUI

extension MessageBubbleView {
    @ViewBuilder
    var agentHeader: some View {
        if message.role == .agent, let identifier = agentName, shouldShowAgentMessage {
            HStack(spacing: 4) {
                AgentIconView(agent: identifier, size: 16)
                Text(agentDisplayName.capitalized)
                    .font(.system(size: 13, weight: .bold))
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    var agentBubble: some View {
        if shouldShowAgentMessage {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MessageContentView(
                            content: message.content,
                            basePath: markdownBasePath,
                            onOpenFileInEditor: onOpenFileInEditor
                        )
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
    }

    var systemMessage: some View {
        Text(message.content)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: false)
    }
}
