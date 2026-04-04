//
//  UserBubble.swift
//  aizen
//
//  Presentation for user-authored chat bubbles and attachments
//

import ACP
import SwiftUI

struct UserBubble<Background: View>: View {
    let content: String
    let timestamp: Date
    let contentBlocks: [ContentBlock]
    let showCopyConfirmation: Bool
    let copyAction: () -> Void
    @ViewBuilder let backgroundView: () -> Background

    @AppStorage(AppearanceSettings.markdownFontFamilyKey) private var chatFontFamily = AppearanceSettings.defaultMarkdownFontFamily
    @AppStorage(AppearanceSettings.markdownFontSizeKey) private var chatFontSize = AppearanceSettings.defaultMarkdownFontSize

    private let maxContentWidth: CGFloat = 420
    private let hPadding: CGFloat = 16
    private let vPadding: CGFloat = 12

    private var chatFont: Font {
        AppearanceSettings.resolvedFont(family: chatFontFamily, size: chatFontSize)
    }

    private var attachmentBlocks: [ContentBlock] {
        var foundFirstText = false
        return contentBlocks.filter { block in
            switch block {
            case .text:
                if !foundFirstText {
                    foundFirstText = true
                    return false
                }
                return true
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
            bubbleContent
                .padding(.horizontal, hPadding)
                .padding(.vertical, vPadding)
                .background(backgroundView())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button {
                        copyAction()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

            if hasAttachments {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(Array(attachmentBlocks.enumerated()), id: \.offset) { _, block in
                        attachmentView(for: block)
                    }
                }
            }

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

    private func formatTimestamp(_ date: Date) -> String {
        DateFormatters.shortTime.string(from: date)
    }
}
