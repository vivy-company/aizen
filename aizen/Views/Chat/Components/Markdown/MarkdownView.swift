//  MarkdownView.swift
//  aizen
//
//  VStack-based markdown renderer using production MarkdownParser
//  Supports streaming, incremental parsing, and text selection
//

import SwiftUI
import AppKit
import Combine
import Markdown

// MARK: - Fixed Text View

/// NSTextView subclass that doesn't trigger layout updates during drawing
class FixedTextView: NSTextView {
    private var isDrawing = false

    override func draw(_ dirtyRect: NSRect) {
        isDrawing = true
        super.draw(dirtyRect)
        isDrawing = false
    }

    override func setFrameSize(_ newSize: NSSize) {
        // Only prevent frame changes during actual drawing to avoid constraint loops
        guard !isDrawing else { return }
        super.setFrameSize(newSize)
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager,
              let container = textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        layoutManager.ensureLayout(for: container)
        let rect = layoutManager.usedRect(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: rect.height + 2)
    }
}

// MARK: - Markdown View

/// Main markdown renderer with cross-block text selection support
struct MarkdownView: View {
    let content: String
    var isStreaming: Bool = false
    var basePath: String? = nil  // Base path for resolving relative URLs (e.g., directory of markdown file)

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = MarkdownViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Group consecutive text blocks for cross-block selection
            let groups = groupBlocks(viewModel.blocks)

            ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                switch group {
                case .textGroup(let blocks):
                    // Render multiple text blocks in a single selectable view
                    CombinedTextBlockView(blocks: blocks)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                        .transition(.opacity)

                case .specialBlock(let block):
                    // Render special blocks separately
                    let isLastBlock = groupIndex == groups.count - 1
                    SpecialBlockRenderer(
                        block: block,
                        isStreaming: isStreaming && isLastBlock,
                        basePath: basePath
                    )
                    .transition(.opacity)

                case .imageRow(let images):
                    // Render consecutive images in a flow layout (wraps to new lines)
                    FlowLayout(spacing: 4) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                            LinkedImageView(url: img.url, alt: img.alt, linkURL: img.linkURL, basePath: basePath)
                        }
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity)
                }
            }

            // Streaming buffer (incomplete content)
            if isStreaming && !viewModel.streamingBuffer.isEmpty {
                StreamingTextView(text: viewModel.streamingBuffer, allowSelection: false)
                    .padding(.vertical, 2)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(isStreaming ? nil : .easeOut(duration: 0.15), value: viewModel.blocks.count)
        .animation(isStreaming ? nil : .easeOut(duration: 0.1), value: viewModel.streamingBuffer)
        .onChange(of: content) { newContent in
            viewModel.parse(newContent, isStreaming: isStreaming)
        }
        .onChange(of: isStreaming) { newIsStreaming in
            viewModel.parse(content, isStreaming: newIsStreaming)
        }
        .onAppear {
            viewModel.parse(content, isStreaming: isStreaming)
        }
    }

    /// Groups consecutive text blocks together for unified selection
    private func groupBlocks(_ blocks: [MarkdownBlock]) -> [BlockGroup] {
        var groups: [BlockGroup] = []
        var currentTextBlocks: [MarkdownBlock] = []
        var currentImageRow: [(url: String, alt: String?, linkURL: String?)] = []

        for block in blocks {
            // Check if this is an image-only paragraph (for badge rows)
            let images = extractImages(from: block)
            if !images.isEmpty {
                // Flush text blocks first
                if !currentTextBlocks.isEmpty {
                    groups.append(.textGroup(currentTextBlocks))
                    currentTextBlocks = []
                }
                currentImageRow.append(contentsOf: images)
            } else {
                // Flush accumulated image row
                if !currentImageRow.isEmpty {
                    groups.append(.imageRow(currentImageRow))
                    currentImageRow = []
                }

                if isTextBlock(block) {
                    currentTextBlocks.append(block)
                } else {
                    // Flush accumulated text blocks
                    if !currentTextBlocks.isEmpty {
                        groups.append(.textGroup(currentTextBlocks))
                        currentTextBlocks = []
                    }
                    groups.append(.specialBlock(block))
                }
            }
        }

        // Flush remaining
        if !currentImageRow.isEmpty {
            groups.append(.imageRow(currentImageRow))
        }
        if !currentTextBlocks.isEmpty {
            groups.append(.textGroup(currentTextBlocks))
        }

        return groups
    }

    /// Extract all images from a block if it contains ONLY images (possibly linked)
    /// Returns empty array if paragraph contains any non-image content (text, code, etc.)
    private func extractImages(from block: MarkdownBlock) -> [(url: String, alt: String?, linkURL: String?)] {
        // Check for standalone .image block
        if case .image(let url, let alt) = block.type {
            return [(url, alt, nil)]
        }

        // Check for paragraph with only images or linked images
        guard case .paragraph(let content) = block.type else { return [] }

        // Filter out whitespace-only text elements and soft/hard breaks
        let significantElements = content.elements.filter { element in
            switch element {
            case .text(let text):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .softBreak, .hardBreak:
                return false  // Ignore line breaks between badges
            default:
                return true
            }
        }

        // Check if ALL significant elements are images or links containing images
        var images: [(url: String, alt: String?, linkURL: String?)] = []

        for element in significantElements {
            switch element {
            case .image(let url, let alt, _):
                images.append((url, alt, nil))

            case .link(let linkContent, let linkURL, _):
                // Check if link contains only an image (filter whitespace and breaks)
                let linkElements = linkContent.elements.filter { el in
                    switch el {
                    case .text(let t):
                        return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    case .softBreak, .hardBreak:
                        return false
                    default:
                        return true
                    }
                }
                if linkElements.count == 1,
                   case .image(let imgURL, let alt, _) = linkElements[0] {
                    images.append((imgURL, alt, linkURL))
                } else {
                    // Link contains non-image content, this is not an image-only paragraph
                    return []
                }

            default:
                // Any other element means this is not an image-only paragraph
                return []
            }
        }

        return images
    }

    /// Check if a block can be rendered as text (supports cross-selection)
    private func isTextBlock(_ block: MarkdownBlock) -> Bool {
        switch block.type {
        case .paragraph(let content):
            // Paragraphs with images need special rendering
            return !content.containsImages
        case .heading, .blockQuote, .list, .thematicBreak, .footnoteReference, .footnoteDefinition:
            return true
        case .codeBlock, .mermaidDiagram, .mathBlock, .table, .image, .htmlBlock:
            return false
        }
    }
}

// MARK: - Block Group

private enum BlockGroup {
    case textGroup([MarkdownBlock])
    case specialBlock(MarkdownBlock)
    case imageRow([(url: String, alt: String?, linkURL: String?)])  // Horizontal row of images/badges
}

// MARK: - Combined Text Block View

/// Renders multiple text blocks using SwiftUI Text with selection support
struct CombinedTextBlockView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        Text(buildAttributedString())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                // Smart spacing based on previous and current block types
                let prevBlock = blocks[index - 1]
                let spacing = spacingBetween(prev: prevBlock.type, current: block.type)
                result.append(AttributedString(spacing))
            }

            switch block.type {
            case .paragraph(let content):
                result.append(content.attributedString(baseFont: .body))

            case .heading(let content, let level):
                result.append(content.attributedString(baseFont: fontForHeading(level: level)))

            case .blockQuote(let nestedBlocks):
                result.append(buildQuoteAttributedString(nestedBlocks))

            case .list(let items, _, _):
                result.append(buildListAttributedString(items))

            case .thematicBreak:
                var hr = AttributedString("───────────────────────────────")
                hr.foregroundColor = .secondary
                result.append(hr)

            case .footnoteReference(let id):
                var fn = AttributedString("[\(id)]")
                fn.font = .footnote
                fn.foregroundColor = .accentColor
                fn.baselineOffset = 4
                result.append(fn)

            case .footnoteDefinition(let id, let defBlocks):
                var fnDef = AttributedString("[\(id)]: ")
                fnDef.font = .callout
                fnDef.foregroundColor = .secondary
                result.append(fnDef)
                for defBlock in defBlocks {
                    if case .paragraph(let content) = defBlock.type {
                        var contentAttr = content.attributedString(baseFont: .callout)
                        contentAttr.foregroundColor = .secondary
                        result.append(contentAttr)
                    }
                }

            default:
                break
            }
        }

        return result
    }

    private func fontForHeading(level: Int) -> Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        case 3: return .title3.weight(.semibold)
        case 4: return .headline
        default: return .body.weight(.medium)
        }
    }

    private func buildQuoteAttributedString(_ blocks: [MarkdownBlock]) -> AttributedString {
        var result = AttributedString("│ ")
        result.foregroundColor = .secondary

        for block in blocks {
            if case .paragraph(let content) = block.type {
                var contentAttr = content.attributedString(baseFont: .body.italic())
                contentAttr.foregroundColor = .secondary
                result.append(contentAttr)
            }
        }

        return result
    }

    private func buildListAttributedString(_ items: [MarkdownListItem]) -> AttributedString {
        var result = AttributedString()

        for (index, item) in items.enumerated() {
            if index > 0 || item.depth > 0 {
                result.append(AttributedString("\n"))
            }

            let indent = String(repeating: "    ", count: item.depth)
            let bullet: String
            if let checkbox = item.checkbox {
                bullet = checkbox == .checked ? "☑ " : "☐ "
            } else if item.listOrdered {
                bullet = "\(item.listStartIndex + item.itemIndex). "
            } else {
                bullet = item.depth == 0 ? "• " : (item.depth == 1 ? "◦ " : "▪ ")
            }

            var bulletAttr = AttributedString(indent + bullet)
            bulletAttr.foregroundColor = .secondary
            result.append(bulletAttr)

            var contentAttr = item.content.attributedString(baseFont: .body)
            if item.checkbox == .checked {
                contentAttr.foregroundColor = .secondary
                contentAttr.strikethroughStyle = .single
            }
            result.append(contentAttr)

            if !item.children.isEmpty {
                result.append(buildListAttributedString(item.children))
            }
        }

        return result
    }

    /// Determine spacing between blocks based on their types
    private func spacingBetween(prev: MarkdownBlockType, current: MarkdownBlockType) -> String {
        // Heading followed by content: single newline (tight)
        if case .heading = prev {
            return "\n"
        }

        // Before a heading: add extra space
        if case .heading = current {
            return "\n\n"
        }

        // Between paragraphs: double newline
        if case .paragraph = prev, case .paragraph = current {
            return "\n\n"
        }

        // List, quote, thematic break: single newline
        switch prev {
        case .list, .blockQuote, .thematicBreak:
            return "\n"
        default:
            break
        }

        switch current {
        case .list, .blockQuote, .thematicBreak:
            return "\n"
        default:
            break
        }

        // Default: single newline for tighter spacing
        return "\n"
    }
}

// MARK: - Special Block Renderer

/// Renders blocks that need special handling (code, mermaid, math, tables, images, paragraphs with images)
struct SpecialBlockRenderer: View {
    let block: MarkdownBlock
    var isStreaming: Bool = false
    var basePath: String? = nil

    var body: some View {
        switch block.type {
        case .paragraph(let content):
            // Paragraph with images
            MixedContentParagraphView(content: content, basePath: basePath)
                .padding(.vertical, 2)

        case .codeBlock(let code, let language, _):
            CodeBlockView(code: code, language: language, isStreaming: isStreaming)
                .padding(.vertical, 4)

        case .mermaidDiagram(let code):
            MermaidDiagramView(code: code, isStreaming: isStreaming)
                .padding(.vertical, 4)

        case .mathBlock(let content):
            MathBlockView(content: content, isBlock: true)
                .padding(.vertical, 8)

        case .table(let rows, let alignments):
            TableBlockView(rows: rows, alignments: alignments)
                .padding(.vertical, 4)

        case .image(let url, let alt):
            MarkdownImageView(url: url, alt: alt, basePath: basePath)
                .padding(.vertical, 4)

        case .htmlBlock(let html):
            Text(html)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 2)

        default:
            EmptyView()
        }
    }
}

// MARK: - Streaming Text View

/// Optimized text view for streaming content with smooth character appearance
struct StreamingTextView: View {
    let text: String
    var allowSelection: Bool = true

    var body: some View {
        if allowSelection {
            Text(text)
                .font(.system(size: NSFont.systemFontSize))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.system(size: NSFont.systemFontSize))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - View Model

@MainActor
final class MarkdownViewModel: ObservableObject {
    @Published var blocks: [MarkdownBlock] = []
    @Published var streamingBuffer: String = ""

    private var lastContent: String = ""
    private var lastIsStreaming: Bool = false
    private var parseTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var pendingContent: String = ""
    private var pendingIsStreaming: Bool = false
    private let streamingIntervalNanos: UInt64 = 30_000_000
    private let streamingLargeIntervalNanos: UInt64 = 60_000_000
    private let streamingLargeContentThreshold = 6000
    private var lastParsedLength: Int = 0
    private var parseGeneration: Int = 0

    func parse(_ content: String, isStreaming: Bool) {
        // Re-parse if content changed OR streaming state changed
        guard content != lastContent || isStreaming != lastIsStreaming else { return }
        lastContent = content
        lastIsStreaming = isStreaming
        parseGeneration += 1
        let generation = parseGeneration
        pendingContent = content
        pendingIsStreaming = isStreaming

        if isStreaming {
            scheduleStreamingParse(generation: generation)
            return
        }

        streamingTask?.cancel()
        streamingTask = nil

        parseTask?.cancel()
        let contentSnapshot = content

        parseTask = Task.detached(priority: .userInitiated) {
            let parser = MarkdownParser()
            let document = parser.parse(contentSnapshot)
            await MainActor.run { [weak self] in
                guard let self, generation == self.parseGeneration else { return }
                self.blocks = document.blocks
                self.streamingBuffer = document.streamingBuffer
                self.lastParsedLength = contentSnapshot.count
            }
        }
    }

    private func scheduleStreamingParse(generation: Int) {
        guard streamingTask == nil else { return }
        streamingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            while true {
                let isStale = await MainActor.run { [weak self] in
                    guard let self else { return true }
                    return generation != self.parseGeneration
                }
                if isStale {
                    break
                }

                let (contentSnapshot, isStreamingSnapshot, interval) = await MainActor.run { [weak self] in
                    guard let self else { return ("", false, UInt64(0)) }
                    let interval = self.pendingContent.count > self.streamingLargeContentThreshold
                        ? self.streamingLargeIntervalNanos
                        : self.streamingIntervalNanos
                    return (self.pendingContent, self.pendingIsStreaming, interval)
                }

                let parser = MarkdownParser()
                let document = parser.parseStreaming(contentSnapshot, isComplete: false)
                await MainActor.run { [weak self] in
                    guard let self, generation == self.parseGeneration else { return }
                    self.blocks = document.blocks
                    self.streamingBuffer = document.streamingBuffer
                    self.lastParsedLength = contentSnapshot.count
                }

                if !isStreamingSnapshot {
                    break
                }

                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
            }

            await MainActor.run { [weak self] in
                self?.streamingTask = nil
            }
        }
    }
}

// MARK: - Block Renderer

struct BlockRenderer: View {
    let block: MarkdownBlock
    var isStreaming: Bool = false

    var body: some View {
        switch block.type {
        case .paragraph(let content):
            // Check if paragraph contains images - render as mixed content if so
            if content.containsImages {
                MixedContentParagraphView(content: content)
                    .padding(.vertical, 2)
            } else {
                SelectableTextView(
                    content: content,
                    baseFont: .systemFont(ofSize: NSFont.systemFontSize),
                    baseColor: .labelColor
                )
                .padding(.vertical, 2)
            }

        case .heading(let content, let level):
            SelectableTextView(
                content: content,
                baseFont: fontForHeading(level: level),
                baseColor: .labelColor
            )
            .fontWeight(level <= 2 ? .bold : .semibold)
            .padding(.top, level <= 2 ? 8 : 4)
            .padding(.bottom, 2)

        case .codeBlock(let code, let language, _):
            if language?.lowercased() == "mermaid" {
                MermaidDiagramView(code: code, isStreaming: isStreaming)
                    .padding(.vertical, 4)
            } else {
                CodeBlockView(
                    code: code,
                    language: language,
                    isStreaming: isStreaming
                )
                .padding(.vertical, 4)
            }

        case .mermaidDiagram(let code):
            MermaidDiagramView(code: code, isStreaming: isStreaming)
                .padding(.vertical, 4)

        case .mathBlock(let content):
            MathBlockView(content: content, isBlock: true)
                .padding(.vertical, 8)

        case .list(let items, _, _):
            ListBlockView(items: items)
                .padding(.vertical, 2)

        case .blockQuote(let blocks):
            BlockQuoteView(blocks: blocks, isStreaming: isStreaming)
                .padding(.vertical, 4)

        case .table(let rows, let alignments):
            TableBlockView(rows: rows, alignments: alignments)
                .padding(.vertical, 4)

        case .image(let url, let alt):
            MarkdownImageView(url: url, alt: alt)
                .padding(.vertical, 4)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 8)

        case .htmlBlock(let html):
            SelectableTextView(
                content: MarkdownInlineContent(text: html),
                baseFont: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                baseColor: .secondaryLabelColor
            )
            .padding(.vertical, 2)

        case .footnoteReference(let id):
            Text("[\(id)]")
                .font(.caption)
                .foregroundColor(.blue)
                .baselineOffset(4)

        case .footnoteDefinition(let id, let blocks):
            VStack(alignment: .leading, spacing: 2) {
                Text("[\(id)]:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(blocks) { nestedBlock in
                    BlockRenderer(block: nestedBlock, isStreaming: false)
                }
            }
            .padding(.leading, 16)
        }
    }

    private func fontForHeading(level: Int) -> NSFont {
        let baseSize = NSFont.systemFontSize
        switch level {
        case 1: return NSFont.systemFont(ofSize: baseSize * 1.5, weight: .bold)
        case 2: return NSFont.systemFont(ofSize: baseSize * 1.3, weight: .bold)
        case 3: return NSFont.systemFont(ofSize: baseSize * 1.15, weight: .semibold)
        case 4: return NSFont.systemFont(ofSize: baseSize * 1.05, weight: .semibold)
        default: return NSFont.systemFont(ofSize: baseSize, weight: .medium)
        }
    }
}

// MARK: - Mixed Content Paragraph View

/// Renders paragraphs that contain images mixed with text
struct MixedContentParagraphView: View {
    let content: MarkdownInlineContent
    var basePath: String? = nil

    var body: some View {
        let segments = splitIntoSegments(content.elements)

        // Check if all segments are images (badge row)
        let allImages = segments.allSatisfy { if case .image = $0 { return true } else { return false } }

        if allImages && segments.count > 1 {
            // Render as horizontal row of badges with wrapping
            FlowLayout(spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if case .image(let url, let alt, let linkURL) = segment {
                        LinkedImageView(url: url, alt: alt, linkURL: linkURL, basePath: basePath)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let elements):
                        if !elements.isEmpty {
                            SelectableTextView(
                                content: MarkdownInlineContent(elements: elements),
                                baseFont: .systemFont(ofSize: NSFont.systemFontSize),
                                baseColor: .labelColor
                            )
                        }
                    case .image(let url, let alt, let linkURL):
                        LinkedImageView(url: url, alt: alt, linkURL: linkURL, basePath: basePath)
                    }
                }
            }
        }
    }

    private enum ContentSegment {
        case text([InlineElement])
        case image(url: String, alt: String?, linkURL: String?)
    }

    private func splitIntoSegments(_ elements: [InlineElement]) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var currentTextElements: [InlineElement] = []

        /// Helper to check if link contains only an image (filtering whitespace and breaks)
        func extractImageFromLink(_ linkContent: MarkdownInlineContent) -> (url: String, alt: String?)? {
            let filtered = linkContent.elements.filter { el in
                switch el {
                case .text(let t): return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                case .softBreak, .hardBreak: return false
                default: return true
                }
            }
            if filtered.count == 1, case .image(let url, let alt, _) = filtered[0] {
                return (url, alt)
            }
            return nil
        }

        /// Helper to flush text elements, filtering out break-only content
        func flushTextElements() {
            // Filter to check if there's any real content (not just breaks)
            let hasContent = currentTextElements.contains { el in
                switch el {
                case .softBreak, .hardBreak: return false
                case .text(let t): return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                default: return true
                }
            }
            if hasContent {
                segments.append(.text(currentTextElements))
            }
            currentTextElements = []
        }

        for element in elements {
            switch element {
            case .image(let url, let alt, _):
                flushTextElements()
                segments.append(.image(url: url, alt: alt, linkURL: nil))

            case .link(let content, let linkURL, _):
                // Check if link contains only an image (badge pattern)
                if let img = extractImageFromLink(content) {
                    flushTextElements()
                    segments.append(.image(url: img.url, alt: img.alt, linkURL: linkURL))
                } else {
                    // Regular link with text
                    currentTextElements.append(element)
                }

            case .softBreak, .hardBreak:
                // Keep breaks for now, but they'll be filtered out if between images
                currentTextElements.append(element)

            default:
                currentTextElements.append(element)
            }
        }

        // Flush remaining text
        flushTextElements()

        return segments
    }
}

// MARK: - Linked Image View

/// Image that can optionally be wrapped in a clickable link
struct LinkedImageView: View {
    let url: String
    let alt: String?
    let linkURL: String?
    var basePath: String? = nil

    var body: some View {
        if let linkURL = linkURL, let destination = URL(string: linkURL) {
            Link(destination: destination) {
                MarkdownImageView(url: url, alt: alt, basePath: basePath)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        } else {
            MarkdownImageView(url: url, alt: alt, basePath: basePath)
        }
    }
}

// MARK: - Selectable Text View

/// NSTextView-based text view that supports selection and renders inline markdown
struct SelectableTextView: NSViewRepresentable {
    let content: MarkdownInlineContent
    let baseFont: NSFont
    let baseColor: NSColor

    func makeNSView(context: Context) -> FixedTextView {
        let textView = FixedTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateNSView(_ textView: FixedTextView, context: Context) {
        let attributed = content.nsAttributedString(baseFont: baseFont, baseColor: baseColor)
        // Only update if content changed
        if textView.attributedString() != attributed {
            textView.textStorage?.setAttributedString(attributed)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FixedTextView, context: Context) -> CGSize? {
        guard let layoutManager = nsView.layoutManager,
              let container = nsView.textContainer else {
            return nil
        }

        let width = proposal.width ?? 500
        container.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)

        let rect = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: max(rect.height + 2, 16))
    }
}

// MARK: - List Block View

struct ListBlockView: View {
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ListItemView(item: item)
            }
        }
    }
}

struct ListItemView: View {
    let item: MarkdownListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                // Indentation
                if item.depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(item.depth) * 16)
                }

                // Checkbox, bullet, or number
                if let checkbox = item.checkbox {
                    Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checkbox == .checked ? .green : .secondary)
                        .font(.body)
                        .frame(width: 16)
                } else if item.listOrdered {
                    Text("\(item.listStartIndex + item.itemIndex).")
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .frame(minWidth: 16, alignment: .trailing)
                } else {
                    Text(bulletForDepth(item.depth))
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .frame(width: 16)
                }

                // Content
                SelectableTextView(
                    content: item.content,
                    baseFont: .systemFont(ofSize: NSFont.systemFontSize),
                    baseColor: item.checkbox == .checked ? .secondaryLabelColor : .labelColor
                )
                .strikethrough(item.checkbox == .checked)
            }

            // Nested items
            ForEach(item.children) { child in
                ListItemView(item: child)
            }
        }
    }

    private func bulletForDepth(_ depth: Int) -> String {
        switch depth % 3 {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }
}

// MARK: - Block Quote View

struct BlockQuoteView: View {
    let blocks: [MarkdownBlock]
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(blocks) { block in
                    BlockRenderer(block: block, isStreaming: isStreaming)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Table Block View

struct TableBlockView: View {
    let rows: [MarkdownTableRow]
    let alignments: [ColumnAlignment]

    @Environment(\.colorScheme) private var colorScheme

    private var headerBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.18)
            : Color(white: 0.93)
    }

    private var evenRowBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.12)
            : Color(white: 0.98)
    }

    private var oddRowBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.1)
            : Color(white: 1.0)
    }

    /// Calculate column widths based on content
    private var columnWidths: [CGFloat] {
        guard let firstRow = rows.first else { return [] }
        let columnCount = firstRow.cells.count

        var widths: [CGFloat] = Array(repeating: 40, count: columnCount) // minimum width

        for row in rows {
            for (index, cell) in row.cells.enumerated() where index < columnCount {
                // Estimate width based on content length
                let text = cell.plainText
                let font = row.isHeader
                    ? NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                    : NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let attributes: [NSAttributedString.Key: Any] = [.font: font]
                let size = (text as NSString).size(withAttributes: attributes)
                let cellWidth = ceil(size.width) + 24 // padding
                widths[index] = max(widths[index], cellWidth)
            }
        }

        return widths
    }

    var body: some View {
        let widths = columnWidths

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { cellIndex, cell in
                        let alignment = cellIndex < alignments.count ? alignments[cellIndex] : .none
                        let width = cellIndex < widths.count ? widths[cellIndex] : 80
                        let isLastColumn = cellIndex == row.cells.count - 1

                        HStack(spacing: 0) {
                            Text(cell.plainText)
                                .font(row.isHeader ? .system(size: NSFont.systemFontSize, weight: .semibold) : .system(size: NSFont.systemFontSize))
                                .textSelection(.enabled)
                        }
                        .frame(minWidth: width, maxWidth: isLastColumn ? .infinity : width, alignment: swiftUIAlignment(for: alignment))
                        .padding(.horizontal, 12)
                        .padding(.vertical, row.isHeader ? 10 : 8)

                        if cellIndex < row.cells.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 1)
                        }
                    }
                }
                .background(
                    row.isHeader
                        ? headerBackground
                        : (rowIndex % 2 == 0 ? evenRowBackground : oddRowBackground)
                )

                if row.isHeader {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                } else if rowIndex < rows.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 3, x: 0, y: 1)
    }

    private func swiftUIAlignment(for alignment: ColumnAlignment) -> Alignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .none: return .leading
        }
    }
}
