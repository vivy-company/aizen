//
//  ChatControlsBar.swift
//  aizen
//
//  Agent selector and mode controls bar
//

import ACP
import SwiftUI

struct ChatControlsBar: View {
    private enum Layout {
        static let rowSpacing: CGFloat = 12
        static let trailingGroupSpacing: CGFloat = 14
        static let iconTextSpacing: CGFloat = 6
        static let controlHeight: CGFloat = 22
        static let iconSize: CGFloat = 15
        static let horizontalPadding: CGFloat = 10
    }

    let currentAgentSession: AgentSession?
    let hasModes: Bool
    let onShowUsage: () -> Void
    let onShowHistory: () -> Void
    let showsUsage: Bool
    private let controlColor: Color = .secondary.opacity(0.85)
    private let controlFont: Font = .system(size: 12, weight: .medium)

    var body: some View {
        HStack(alignment: .center, spacing: Layout.rowSpacing) {
            if let agentSession = currentAgentSession, !agentSession.availableConfigOptions.isEmpty {
                AgentConfigMenu(session: agentSession, showsBackground: false)
            }

            if hasModes, let agentSession = currentAgentSession, agentSession.availableConfigOptions.isEmpty {
                ModeSelectorView(session: agentSession, showsBackground: false)
            }

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: Layout.trailingGroupSpacing) {
                if showsUsage {
                    Button(action: onShowUsage) {
                        HStack(spacing: Layout.iconTextSpacing) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: Layout.iconSize, weight: .regular))
                                .frame(width: Layout.iconSize, height: Layout.iconSize)
                            Text("Usage")
                        }
                        .frame(height: Layout.controlHeight)
                        .font(controlFont)
                        .foregroundStyle(controlColor)
                    }
                    .buttonStyle(.plain)
                    .help("Usage")
                }

                Button(action: onShowHistory) {
                    HStack(spacing: Layout.iconTextSpacing) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: Layout.iconSize, weight: .regular))
                            .frame(width: Layout.iconSize, height: Layout.iconSize)
                        Text("History")
                    }
                    .frame(height: Layout.controlHeight)
                    .font(controlFont)
                    .foregroundStyle(controlColor)
                }
                .buttonStyle(.plain)
                .help("Session history")
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatAttachmentsBar: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 10
        static let chipSpacing: CGFloat = 8
    }

    let attachments: [ChatAttachment]
    let onRemoveAttachment: (ChatAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.chipSpacing) {
                ForEach(attachments) { attachment in
                    ChatAttachmentChip(attachment: attachment) {
                        onRemoveAttachment(attachment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.horizontalPadding)
    }
}
