//
//  ACPContentViews.swift
//  aizen
//
//  Shared views for rendering ACP content blocks
//

import SwiftUI
import CodeEditLanguages
import CodeEditSourceEditor

// MARK: - Attachment Glass Card

struct AttachmentGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var tintColor: Color {
        colorScheme == .dark ? .black.opacity(0.18) : .white.opacity(0.5)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? .black.opacity(0.08) : .white.opacity(0.04)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .background { glassBackground(shape: shape) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(strokeColor, lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private func glassBackground(shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            ZStack {
                GlassEffectContainer {
                    shape
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular.tint(tintColor), in: shape)
                }
                .allowsHitTesting(false)

                shape
                    .fill(scrimColor)
                    .allowsHitTesting(false)
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Image Attachment Card (compact chip with click-to-preview)

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

// MARK: - Image Detail Sheet

private struct ImageDetailSheet: View {
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

// MARK: - User Attachment Chip (for displaying file attachments in user messages)

struct UserAttachmentChip: View {
    let name: String
    let uri: String

    private var filePath: String {
        if uri.hasPrefix("file://") {
            return URL(string: uri)?.path ?? uri
        }
        return uri
    }

    var body: some View {
        AttachmentChip(
            title: name,
            icon: AnyView(FileIconView(path: filePath, size: 16)),
            detailView: nil,
            style: AttachmentChip.Style(showsDelete: false, showsHoverFade: false)
        )
    }
}

// MARK: - Resource Content View

struct ACPResourceView: View {
    let uri: String
    let mimeType: String?
    let text: String?

    @State private var highlightedText: AttributedString?
    @AppStorage("editorTheme") private var editorTheme: String = "Aizen Dark"
    @AppStorage("editorThemeLight") private var editorThemeLight: String = "Aizen Light"
    @AppStorage("editorUsePerAppearanceTheme") private var usePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return editorTheme }
        return colorScheme == .dark ? editorTheme : editorThemeLight
    }

    private let highlighter = TreeSitterHighlighter()

    private var isCodeFile: Bool {
        LanguageDetection.isCodeFile(mimeType: mimeType, uri: uri)
    }

    private var detectedLanguage: CodeLanguage {
        LanguageDetection.detectLanguage(mimeType: mimeType, uri: uri, content: text)
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

                if isCodeFile {
                    HorizontalOnlyScrollView(showsIndicators: true) {
                        Group {
                            if let highlighted = highlightedText {
                                Text(highlighted)
                            } else {
                                Text(text)
                                    .foregroundColor(.primary)
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                    }
                    .task(id: text) {
                        await performHighlight(text)
                    }
                } else {
                    Text(text)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }

    private func performHighlight(_ text: String) async {
        do {
            let theme = GhosttyThemeParser.loadTheme(named: effectiveThemeName) ?? defaultTheme()

            let attributed = try await highlighter.highlightCode(
                text,
                language: detectedLanguage,
                theme: theme
            )
            highlightedText = attributed
        } catch {
            highlightedText = AttributedString(text)
        }
    }

    private func defaultTheme() -> EditorTheme {
        let bg = NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        let fg = NSColor(red: 0.8, green: 0.84, blue: 0.96, alpha: 1.0)

        return EditorTheme(
            text: .init(color: fg),
            insertionPoint: fg,
            invisibles: .init(color: .systemGray),
            background: bg,
            lineHighlight: bg.withAlphaComponent(0.05),
            selection: .selectedTextBackgroundColor,
            keywords: .init(color: .systemPurple),
            commands: .init(color: .systemBlue),
            types: .init(color: .systemYellow),
            attributes: .init(color: .systemRed),
            variables: .init(color: .systemCyan),
            values: .init(color: .systemOrange),
            numbers: .init(color: .systemOrange),
            strings: .init(color: .systemGreen),
            characters: .init(color: .systemGreen),
            comments: .init(color: .systemGray)
        )
    }
}
