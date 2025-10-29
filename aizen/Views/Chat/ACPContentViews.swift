//
//  ACPContentViews.swift
//  aizen
//
//  Shared views for rendering ACP content blocks
//

import SwiftUI
import HighlightSwift

// MARK: - Image Content View

struct ACPImageView: View {
    let data: String
    let mimeType: String

    var body: some View {
        Group {
            if let imageData = Data(base64Encoded: data),
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 400, maxHeight: 300)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            } else {
                HStack {
                    Image(systemName: "photo")
                    Text("chat.image.invalid", bundle: .main)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Resource Content View

struct ACPResourceView: View {
    let uri: String
    let mimeType: String?
    let text: String?

    private var isCodeFile: Bool {
        LanguageDetection.isCodeFile(mimeType: mimeType, uri: uri)
    }

    private var detectedLanguage: HighlightLanguage? {
        LanguageDetection.detectHighlightLanguage(mimeType: mimeType, uri: uri)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                Link(uri, destination: URL(string: uri) ?? URL(fileURLWithPath: "/"))
                    .font(.callout)
                Spacer()
            }

            if let mimeType = mimeType {
                Text(String(format: String(localized: "chat.resource.type"), mimeType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let text = text {
                Divider()

                if let language = detectedLanguage {
                    CodeText(text)
                        .highlightLanguage(language)
                        .codeTextColors(.theme(.github))
                        .codeTextStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(text)
                        .font(.system(.body, design: isCodeFile ? .monospaced : .default))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}
