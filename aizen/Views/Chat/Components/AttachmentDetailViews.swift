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
                MarkdownView(content: content, isStreaming: false)
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

struct InputAttachmentDetailView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss

    @State private var fileContent: String?
    @State private var image: NSImage?
    @State private var fileSize: String = ""

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar {
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                    Text(fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                DetailCloseButton {
                    dismiss()
                }
            }

            Divider()

            Group {
                if let image = image {
                    ImageDetailBody(image: image)
                } else if let content = fileContent {
                    TextDetailBody(text: content, font: .system(.body, design: .monospaced))
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            FileIconView(path: url.path, size: 48)

                            Text("chat.preview.unavailable", bundle: .main)
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                }
            }
        }
        .frame(width: 700, height: 500)
        .onAppear {
            loadFileContent()
        }
    }

    private func loadFileContent() {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        if let loadedImage = NSImage(contentsOf: url) {
            image = loadedImage
            return
        }

        if let content = try? String(contentsOf: url, encoding: .utf8) {
            fileContent = String(content.prefix(10000))
            if content.count > 10000 {
                fileContent! += "\n\n... (content truncated)"
            }
        }
    }
}
