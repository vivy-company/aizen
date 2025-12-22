//
//  MarkdownContentView.swift
//  aizen
//
//  Main markdown rendering components
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

    @State private var cachedBlocks: [MarkdownBlock] = []
    @State private var cachedContentHash: Int = 0
    @State private var pendingContentHash: Int = 0
    @State private var parseTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cachedBlocks) { block in
                MarkdownBlockView(
                    block: block,
                    isStreaming: isStreaming,
                    isLast: block.id == cachedBlocks.last?.id
                )
            }
        }
        .onAppear {
            updateCacheIfNeeded()
        }
        .onChange(of: content) { _ in
            updateCacheIfNeeded()
        }
        .onChange(of: isStreaming) { streaming in
            if !streaming {
                forceUpdateCache()
            }
        }
        .onDisappear {
            parseTask?.cancel()
            parseTask = nil
        }
    }

    private func updateCacheIfNeeded() {
        let contentHash = content.hashValue
        guard cachedContentHash != contentHash else { return }
        guard pendingContentHash != contentHash else { return }

        pendingContentHash = contentHash
        parseTask?.cancel()

        let contentSnapshot = content
        parseTask = Task { @MainActor in
            // Debounce rapid streaming updates
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled else { return }

            let blocks = await Task.detached(priority: .userInitiated) {
                let document = Document(parsing: contentSnapshot)
                return Self.convertMarkdown(document)
            }.value

            guard !Task.isCancelled else { return }
            if pendingContentHash == contentHash {
                pendingContentHash = 0
            }
            if contentSnapshot == content {
                cachedBlocks = blocks
                cachedContentHash = contentHash
            }
        }
    }

    private func forceUpdateCache() {
        let contentHash = content.hashValue
        pendingContentHash = contentHash
        parseTask?.cancel()

        let contentSnapshot = content
        parseTask = Task { @MainActor in
            let blocks = await Task.detached(priority: .userInitiated) {
                let document = Document(parsing: contentSnapshot)
                return Self.convertMarkdown(document)
            }.value

            if contentSnapshot == content {
                cachedBlocks = blocks
                cachedContentHash = contentHash
                pendingContentHash = 0
            }
        }
    }

    private static func convertMarkdown(_ document: Document) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = 0

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
                    let imageData = images.compactMap { image -> (url: String, alt: String?)? in
                        if case .imageRow(let items) = image.type, let first = items.first {
                            return first
                        }
                        if case .image(let url, let alt) = image.type {
                            return (url: url, alt: alt)
                        }
                        return nil
                    }
                    blocks.append(MarkdownBlock(.imageRow(imageData), index: index))
                } else {
                    let attributedText = renderInlineContent(paragraph.children)
                    if !attributedText.characters.isEmpty {
                        blocks.append(MarkdownBlock(.paragraph(attributedText), index: index))
                    }
                }
            } else if let heading = child as? Heading {
                let attributedText = renderInlineContent(heading.children)
                blocks.append(MarkdownBlock(.heading(attributedText, level: heading.level), index: index))
            } else if let codeBlock = child as? CodeBlock {
                // Check for mermaid diagram
                if codeBlock.language?.lowercased() == "mermaid" {
                    blocks.append(MarkdownBlock(.mermaidDiagram(codeBlock.code), index: index))
                } else {
                    blocks.append(MarkdownBlock(.codeBlock(codeBlock.code, language: codeBlock.language), index: index))
                }
            } else if let list = child as? UnorderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(MarkdownBlock(.list(items, isOrdered: false), index: index))
            } else if let list = child as? OrderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(MarkdownBlock(.list(items, isOrdered: true), index: index))
            } else if let blockQuote = child as? BlockQuote {
                let text = renderBlockQuoteContent(blockQuote.children)
                blocks.append(MarkdownBlock(.blockQuote(text), index: index))
            } else if let table = child as? Markdown.Table {
                let headerCells = table.head.cells.map { renderInlineContent($0.children) }
                var bodyRows: [[AttributedString]] = []
                for row in table.body.rows {
                    let rowCells = row.cells.map { renderInlineContent($0.children) }
                    bodyRows.append(Array(rowCells))
                }
                blocks.append(MarkdownBlock(.table(header: Array(headerCells), rows: bodyRows, alignments: table.columnAlignments), index: index))
            }
            index += 1
        }

        return blocks
    }

    private static func extractImagesFromParagraph(_ paragraph: Paragraph) -> [MarkdownBlock] {
        var images: [MarkdownBlock] = []
        var imgIndex = 0

        for child in paragraph.children {
            // Direct image
            if let image = child as? Markdown.Image {
                images.append(MarkdownBlock(.image(url: image.source ?? "", alt: extractImageAlt(image)), index: imgIndex))
                imgIndex += 1
            }
            // Image wrapped in link (like badges)
            else if let link = child as? Markdown.Link {
                for linkChild in link.children {
                    if let image = linkChild as? Markdown.Image {
                        images.append(MarkdownBlock(.image(url: image.source ?? "", alt: extractImageAlt(image)), index: imgIndex))
                        imgIndex += 1
                    }
                }
            }
        }

        return images
    }

    private static func extractImageAlt(_ image: Markdown.Image) -> String? {
        // Extract alt text from image children
        var alt = ""
        for child in image.children {
            if let text = child as? Markdown.Text {
                alt += text.string
            }
        }
        return alt.isEmpty ? nil : alt
    }

    private static func renderInlineContent(_ inlineElements: some Sequence<Markup>) -> AttributedString {
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

    private static func renderBlockQuoteContent(_ children: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for child in children {
            if let paragraph = child as? Paragraph {
                result += renderInlineContent(paragraph.children)
            }
        }

        return result
    }
}

// MARK: - Markdown Block View

/// Individual block renderer with stable identity
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var isStreaming: Bool = false
    var isLast: Bool = false

    var body: some View {
        switch block.type {
        case .paragraph(let attributedText):
            Text(attributedText)
                .textSelection(.enabled)
                .opacity(isStreaming && isLast ? 0.9 : 1.0)
        case .heading(let attributedText, let level):
            Text(attributedText)
                .font(fontForHeading(level: level))
                .fontWeight(.bold)
                .textSelection(.enabled)
        case .codeBlock(let code, let language):
            CodeBlockView(code: code, language: language, isStreaming: isStreaming && isLast)
        case .list(let items, let isOrdered):
            MarkdownListView(items: items, isOrdered: isOrdered)
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
            MarkdownImageRowView(images: images)
        case .mermaidDiagram(let code):
            MermaidDiagramView(code: code)
                .frame(height: 400)
        case .table(let header, let rows, let alignments):
            MarkdownTableView(header: header, rows: rows, alignments: alignments)
        }
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
