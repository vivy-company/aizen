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

struct ReviewCommentsDetailView: View {
    let content: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("Review Comments")
                    .font(.headline)
            } trailing: {
                DetailDoneButton {
                    dismiss()
                }
            }

            Divider()

            ScrollView {
                MarkdownView(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct BuildErrorDetailView: View {
    let content: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Build Error")
                        .font(.headline)
                }
            } trailing: {
                DetailDoneButton {
                    dismiss()
                }
            }

            Divider()

            TextDetailBody(
                text: content,
                font: .system(size: 11, design: .monospaced),
                showsBackground: true
            )
        }
        .frame(width: 600, height: 400)
    }
}
