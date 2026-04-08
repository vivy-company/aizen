//
//  AttachmentDetailViews.swift
//  aizen
//
//  Detail sheet views for chat attachments
//

import SwiftUI

struct ImageAttachmentDetailView: View {
    let data: Data
    @Environment(\.dismiss) var dismiss

    private var stats: ImageAttachmentStats {
        ImageAttachmentStats(image: NSImage(data: data), data: data)
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pasted Image")
                        .font(.headline)
                    if let size = stats.sizeLabel {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } trailing: {
                DetailCloseButton {
                    dismiss()
                }
            }

            Divider()

            ImageDetailBody(image: stats.image)
        }
        .frame(width: 700, height: 500)
    }
}

struct TextAttachmentDetailView: View {
    let content: String
    var showsCopyButton: Bool = false
    @Environment(\.dismiss) var dismiss

    private var stats: TextAttachmentStats {
        TextAttachmentStats(text: content)
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar {
                TextAttachmentHeader(stats: stats)
            } trailing: {
                HStack(spacing: 10) {
                    if showsCopyButton {
                        CopyButton(text: content, iconSize: 14)
                    }
                    DetailCloseButton {
                        dismiss()
                    }
                }
            }

            Divider()

            TextDetailBody(
                text: content,
                font: .system(size: 12, design: .monospaced),
                showsBackground: true
            )
        }
        .frame(width: 700, height: 500)
    }
}
