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

    let configOptions: [SessionConfigOption]
    let availableModes: [ModeInfo]
    let currentModeId: String?
    let isSessionStreaming: Bool
    let onSelectMode: (String) -> Void
    let onSetConfigOption: (String, String) -> Void
    let onToggleConfigOption: (String, Bool) -> Void
    let onShowUsage: () -> Void
    let onShowHistory: () -> Void
    let showsUsage: Bool
    private let controlColor: Color = .secondary.opacity(0.85)
    private let controlFont: Font = .system(size: 12, weight: .medium)

    var body: some View {
        HStack(alignment: .center, spacing: Layout.rowSpacing) {
            if !configOptions.isEmpty {
                AgentConfigMenu(
                    configOptions: configOptions,
                    isStreaming: isSessionStreaming,
                    showsBackground: false,
                    onSetConfigOption: onSetConfigOption,
                    onToggleConfigOption: onToggleConfigOption
                )
            }

            if !availableModes.isEmpty, configOptions.isEmpty {
                ModeSelectorView(
                    availableModes: availableModes,
                    currentModeId: currentModeId,
                    isStreaming: isSessionStreaming,
                    showsBackground: false,
                    onSelectMode: onSelectMode
                )
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
    let onRemoveAttachment: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.chipSpacing) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                    ChatAttachmentChip(attachment: attachment) {
                        onRemoveAttachment(index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.horizontalPadding)
    }
}
