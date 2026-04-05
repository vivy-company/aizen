//
//  ACPContentViews+Images.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import Foundation
import SwiftUI

struct ImageAttachmentCardView: View {
    let data: String

    @State private var showingDetail = false

    private var imageData: Data? {
        Data(base64Encoded: data)
    }

    private var nsImage: NSImage? {
        guard let imageData else { return nil }
        return NSImage(data: imageData)
    }

    private var stats: ImageAttachmentStats {
        ImageAttachmentStats(image: nsImage, data: imageData)
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            AttachmentGlassCard(cornerRadius: 10) {
                HStack(spacing: 6) {
                    if let image = nsImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple)
                    }

                    Text(String(localized: "chat.content.image"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let dimensions = stats.dimensionsLabel() {
                        Text(dimensions)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ImageDetailSheet(data: data)
        }
    }
}

struct ImageDetailSheet: View {
    let data: String
    @Environment(\.dismiss) var dismiss

    private var imageData: Data? {
        Data(base64Encoded: data)
    }

    private var nsImage: NSImage? {
        guard let imageData else { return nil }
        return NSImage(data: imageData)
    }

    private var stats: ImageAttachmentStats {
        ImageAttachmentStats(image: nsImage, data: imageData)
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Image")
                        .font(.headline)
                    HStack(spacing: 8) {
                        if let dimensions = stats.dimensionsLabel(separator: " × ") {
                            Text(dimensions)
                        }
                        if let fileSize = stats.sizeLabel {
                            Text(fileSize)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } trailing: {
                DetailCloseButton {
                    dismiss()
                }
            }

            Divider()

            ImageDetailBody(image: nsImage)
        }
        .frame(width: 700, height: 500)
    }
}
