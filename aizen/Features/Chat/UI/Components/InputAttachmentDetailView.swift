//
//  InputAttachmentDetailView.swift
//  aizen
//

import SwiftUI

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
