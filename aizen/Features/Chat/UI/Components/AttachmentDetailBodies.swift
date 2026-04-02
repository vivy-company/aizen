//
//  AttachmentDetailBodies.swift
//  aizen
//
//  Shared content bodies for attachment detail sheets
//

import SwiftUI

struct ImageDetailBody: View {
    let image: NSImage?

    var body: some View {
        ScrollView {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Unable to display image")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

struct TextDetailBody: View {
    let text: String
    var font: Font = .system(.body, design: .monospaced)
    var showsBackground: Bool = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .modifier(DetailBodyBackground(enabled: showsBackground))
    }
}

struct TextAttachmentStats {
    let lineCount: Int
    let charCount: Int

    init(text: String) {
        lineCount = text.components(separatedBy: .newlines).count
        charCount = text.count
    }

    var lineLabel: String {
        "\(lineCount) lines"
    }

    var charLabel: String {
        "\(charCount) characters"
    }

    var displayInfo: String {
        if lineCount > 1 {
            return lineLabel
        }
        return "\(charCount) chars"
    }
}

struct TextAttachmentHeader: View {
    let stats: TextAttachmentStats
    var title: String = "Pasted Text"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            HStack(spacing: 8) {
                Text(stats.lineLabel)
                Text(stats.charLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct ImageAttachmentStats {
    let image: NSImage?
    let data: Data?

    init(image: NSImage?, data: Data?) {
        self.image = image
        self.data = data
    }

    func dimensionsLabel(separator: String = "×") -> String? {
        guard let image else { return nil }
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        return "\(width)\(separator)\(height)"
    }

    var sizeLabel: String? {
        guard let data else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

private struct DetailBodyBackground: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.background(Color(nsColor: .textBackgroundColor))
        } else {
            content
        }
    }
}
