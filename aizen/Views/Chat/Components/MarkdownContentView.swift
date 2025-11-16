//
//  MarkdownContentView.swift
//  aizen
//
//  Markdown rendering components
//

import SwiftUI
import Markdown

// MARK: - Message Content View

struct MessageContentView: View {
    let content: String
    var isComplete: Bool = true

    var body: some View {
        MarkdownRenderedView(content: content, isStreaming: !isComplete)
    }
}

// MARK: - Markdown Rendered View

struct MarkdownRenderedView: View {
    let content: String
    var isStreaming: Bool = false

    private var renderedBlocks: [MarkdownBlock] {
        let document = Document(parsing: content)
        return convertMarkdown(document)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(renderedBlocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .paragraph(let attributedText):
                    Text(attributedText)
                        .textSelection(.enabled)
                        .opacity(isStreaming && index == renderedBlocks.count - 1 ? 0.9 : 1.0)
                case .heading(let attributedText, let level):
                    Text(attributedText)
                        .font(fontForHeading(level: level))
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                case .codeBlock(let code, let language):
                    CodeBlockView(code: code, language: language)
                case .list(let items, let isOrdered):
                    ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(isOrdered ? "\(itemIndex + 1)." : "•")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .textSelection(.enabled)
                        }
                    }
                case .blockQuote(let attributedText):
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3)
                        Text(attributedText)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                case .image(let url, let alt):
                    MarkdownImageView(url: url, alt: alt)
                case .imageRow(let images):
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, imageInfo in
                            MarkdownImageView(url: imageInfo.url, alt: imageInfo.alt)
                        }
                    }
                case .mermaidDiagram(let code):
                    MermaidDiagramView(code: code)
                        .frame(height: 400)
                }
            }
        }
    }

    private func convertMarkdown(_ document: Document) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        for child in document.children {
            if let paragraph = child as? Paragraph {
                // Check if paragraph contains only images (badges case)
                let images = extractImagesFromParagraph(paragraph)

                // Check if there's any text content besides images
                var hasText = false
                for child in paragraph.children {
                    if let text = child as? Markdown.Text, !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        hasText = true
                        break
                    }
                    if child is Markdown.SoftBreak || child is Markdown.LineBreak {
                        continue
                    }
                    // If it's not an image or link containing image, it's other content
                    if !(child is Markdown.Image) && !(child is Markdown.Link) {
                        hasText = true
                        break
                    }
                }

                if !images.isEmpty && !hasText {
                    // Multiple images in same paragraph - render as image row
                    blocks.append(.imageRow(images.map { image in
                        if case .image(let url, let alt) = image {
                            return (url: url, alt: alt)
                        }
                        return (url: "", alt: nil)
                    }))
                } else {
                    let attributedText = renderInlineContent(paragraph.children)
                    if !attributedText.characters.isEmpty {
                        blocks.append(.paragraph(attributedText))
                    }
                }
            } else if let heading = child as? Heading {
                let attributedText = renderInlineContent(heading.children)
                blocks.append(.heading(attributedText, level: heading.level))
            } else if let codeBlock = child as? CodeBlock {
                // Check for mermaid diagram
                if codeBlock.language?.lowercased() == "mermaid" {
                    blocks.append(.mermaidDiagram(codeBlock.code))
                } else {
                    blocks.append(.codeBlock(codeBlock.code, language: codeBlock.language))
                }
            } else if let list = child as? UnorderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(.list(items, isOrdered: false))
            } else if let list = child as? OrderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(.list(items, isOrdered: true))
            } else if let blockQuote = child as? BlockQuote {
                let text = renderBlockQuoteContent(blockQuote.children)
                blocks.append(.blockQuote(text))
            }
        }

        return blocks
    }

    private func extractImagesFromParagraph(_ paragraph: Paragraph) -> [MarkdownBlock] {
        var images: [MarkdownBlock] = []

        for child in paragraph.children {
            // Direct image
            if let image = child as? Markdown.Image {
                images.append(.image(url: image.source ?? "", alt: extractImageAlt(image)))
            }
            // Image wrapped in link (like badges)
            else if let link = child as? Markdown.Link {
                for linkChild in link.children {
                    if let image = linkChild as? Markdown.Image {
                        images.append(.image(url: image.source ?? "", alt: extractImageAlt(image)))
                    }
                }
            }
        }

        return images
    }

    private func extractImageAlt(_ image: Markdown.Image) -> String? {
        // Extract alt text from image children
        var alt = ""
        for child in image.children {
            if let text = child as? Markdown.Text {
                alt += text.string
            }
        }
        return alt.isEmpty ? nil : alt
    }

    private func renderInlineContent(_ inlineElements: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for element in inlineElements {
            if let text = element as? Markdown.Text {
                result += AttributedString(text.string)
            } else if let strong = element as? Strong {
                var boldText = renderInlineContent(strong.children)
                boldText.font = .body.bold()
                result += boldText
            } else if let emphasis = element as? Emphasis {
                var italicText = renderInlineContent(emphasis.children)
                italicText.font = .body.italic()
                result += italicText
            } else if let code = element as? InlineCode {
                var codeText = AttributedString(code.code)
                codeText.font = .system(.body, design: .monospaced)
                codeText.backgroundColor = Color(nsColor: .textBackgroundColor)
                result += codeText
            } else if let link = element as? Markdown.Link {
                var linkText = renderInlineContent(link.children)
                if let url = URL(string: link.destination ?? "") {
                    linkText.link = url
                }
                linkText.foregroundColor = Color.blue
                linkText.underlineStyle = .single
                result += linkText
            } else if let strikethrough = element as? Strikethrough {
                var strikethroughText = renderInlineContent(strikethrough.children)
                strikethroughText.strikethroughStyle = .single
                result += strikethroughText
            } else if let paragraph = element as? Paragraph {
                result += renderInlineContent(paragraph.children)
            }
        }

        return result
    }

    private func renderBlockQuoteContent(_ children: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for child in children {
            if let paragraph = child as? Paragraph {
                result += renderInlineContent(paragraph.children)
            }
        }

        return result
    }

    private func fontForHeading(level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        default: return .body
        }
    }
}

// MARK: - Markdown Block Type

enum MarkdownBlock {
    case paragraph(AttributedString)
    case heading(AttributedString, level: Int)
    case codeBlock(String, language: String?)
    case list([AttributedString], isOrdered: Bool)
    case blockQuote(AttributedString)
    case image(url: String, alt: String?)
    case imageRow([(url: String, alt: String?)])
    case mermaidDiagram(String)
}

// MARK: - Markdown Image View

struct MarkdownImageView: View {
    let url: String
    let alt: String?

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(image.size.width, 600), height: min(image.size.height, 400))
                    .cornerRadius(4)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Failed to load image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let alt = alt, !alt.isEmpty {
                            Text(alt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let imageURL = URL(string: url) else {
            error = "Invalid URL"
            isLoading = false
            return
        }

        // Check if it's a local file path
        if imageURL.scheme == nil || imageURL.scheme == "file" {
            // Local file
            if let nsImage = NSImage(contentsOfFile: imageURL.path) {
                await MainActor.run {
                    self.image = nsImage
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.error = "File not found"
                    self.isLoading = false
                }
            }
        } else {
            // Remote URL
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                if let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        self.image = nsImage
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.error = "Invalid image data"
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Mermaid Diagram View

import WebKit

struct MermaidDiagramView: NSViewRepresentable {
    let code: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <script type="module">
                    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
                    mermaid.initialize({
                        startOnLoad: true,
                        theme: 'dark',
                        themeVariables: {
                            darkMode: true,
                            background: 'transparent',
                            mainBkg: 'transparent',
                            primaryColor: '#89b4fa',
                            primaryTextColor: '#cdd6f4',
                            primaryBorderColor: '#89b4fa',
                            lineColor: '#6c7086',
                            secondaryColor: '#f5c2e7',
                            tertiaryColor: '#94e2d5',
                            fontSize: '14px',
                            nodeBorder: '#6c7086',
                            clusterBkg: 'transparent',
                            clusterBorder: '#6c7086',
                            defaultLinkColor: '#6c7086',
                            titleColor: '#cdd6f4',
                            edgeLabelBackground: 'transparent',
                            nodeTextColor: '#cdd6f4'
                        }
                    });
                </script>
                <style>
                    body {
                        background-color: transparent;
                        color: #cdd6f4;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                        margin: 16px;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                    }
                    .mermaid {
                        background-color: transparent;
                    }
                </style>
            </head>
            <body>
                <pre class="mermaid">
            \(code)
                </pre>
            </body>
            </html>
            """

        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Adjust height after content loads
            webView.evaluateJavaScript("document.body.scrollHeight") { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        webView.frame.size.height = height + 32 // Add padding
                    }
                }
            }
        }
    }
}
