//
//  ChatInputView.swift
//  aizen
//
//  Chat input components and helpers
//

import SwiftUI

// MARK: - Chat Attachment Chip

struct ChatAttachmentChip: View {
    let attachment: ChatAttachment
    let onDelete: () -> Void

    var body: some View {
        AttachmentChip(
            title: attachment.displayName,
            icon: AnyView(attachmentIcon),
            detailView: AnyView(attachmentDetailView),
            style: AttachmentChip.Style(),
            onDelete: onDelete
        )
    }

    @ViewBuilder
    private var attachmentIcon: some View {
        switch attachment {
        case .file(let url):
            FileIconView(path: url.path, size: 16)
        case .image(let data, _):
            let maxInlinePreviewBytes = 2 * 1024 * 1024
            if data.count <= maxInlinePreviewBytes, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
            }
        case .text:
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        case .reviewComments:
            Image(systemName: "text.bubble")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
        case .buildError:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var attachmentDetailView: some View {
        switch attachment {
        case .file(let url):
            InputAttachmentDetailView(url: url)
        case .image(let data, _):
            ImageAttachmentDetailView(data: data)
        case .text(let content):
            TextAttachmentDetailView(content: content)
        case .reviewComments(let content):
            ReviewCommentsDetailView(content: content)
        case .buildError(let content):
            BuildErrorDetailView(content: content)
        }
    }
}
