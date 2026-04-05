//
//  MessageBubbleView+Presentation.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import ACP
import SwiftUI

extension MessageBubbleView {
    var alignment: HorizontalAlignment {
        switch message.role {
        case .user:
            return .trailing
        case .agent:
            return .leading
        case .system:
            return .center
        }
    }

    var bubbleAlignment: Alignment {
        switch message.role {
        case .user:
            return .trailing
        case .agent:
            return .leading
        case .system:
            return .center
        }
    }

    var agentAttachmentBlocks: [ContentBlock] {
        message.contentBlocks.filter { block in
            switch block {
            case .text:
                return false
            case .image, .audio, .resource, .resourceLink:
                return true
            }
        }
    }

    var shouldShowAgentMessage: Bool {
        guard message.role == .agent else { return true }
        let hasContent = !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasContent || !agentAttachmentBlocks.isEmpty
    }

    var agentDisplayName: String {
        guard let agentName else { return "" }
        if let meta = AgentRegistry.shared.getMetadata(for: agentName) {
            return meta.name
        }
        return agentName
    }

    @ViewBuilder
    var backgroundView: some View {
        Color.clear
            .background(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
            }
    }

    func copyMessage() {
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

    func formatTimestamp(_ date: Date) -> String {
        DateFormatters.shortTime.string(from: date)
    }
}
