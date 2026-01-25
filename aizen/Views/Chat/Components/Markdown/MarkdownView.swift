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
    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing
    @StateObject private var viewModel = MarkdownViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: blockSpacing) {
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
                    FlowLayout(spacing: 4) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                            LinkedImageView(url: img.url, alt: img.alt, linkURL: img.linkURL, basePath: basePath)
                        }
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity)
                    
                case .semanticBlock(let type, let title, let contentBlocks):
                    SemanticBlockWithContentView(
                        type: type,
                        title: title,
                        contentBlocks: contentBlocks,
                        isStreaming: isStreaming && groupIndex == groups.count - 1
                    )
                    .padding(.vertical, 2)
                    .transition(.opacity)
                }
            }

            if isStreaming && !viewModel.streamingBuffer.isEmpty {
                let buffer = viewModel.streamingBuffer
                let isPendingBlock = buffer.hasPrefix("```") || 
                                     buffer.hasPrefix("$$") || 
                                     buffer.trimmingCharacters(in: .whitespaces).hasPrefix("|")
                
                if isPendingBlock {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Rendering...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .transition(.opacity)
                } else {
                    StreamingTextView(text: buffer, allowSelection: false)
                        .padding(.vertical, 2)
                        .transition(.opacity)
                }
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

    private func groupBlocks(_ blocks: [MarkdownBlock]) -> [BlockGroup] {
        var groups: [BlockGroup] = []
        var currentTextBlocks: [MarkdownBlock] = []
        var currentImageRow: [(url: String, alt: String?, linkURL: String?)] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            
            let images = extractImages(from: block)
            if !images.isEmpty {
                if !currentTextBlocks.isEmpty {
                    groups.append(.textGroup(currentTextBlocks))
                    currentTextBlocks = []
                }
                currentImageRow.append(contentsOf: images)
                index += 1
                continue
            }
            
            if !currentImageRow.isEmpty {
                groups.append(.imageRow(currentImageRow))
                currentImageRow = []
            }
            
            if let emojiHeader = detectStandaloneEmojiHeader(from: block) {
                if !currentTextBlocks.isEmpty {
                    groups.append(.textGroup(currentTextBlocks))
                    currentTextBlocks = []
                }
                
                var contentBlocks: [MarkdownBlock] = []
                index += 1
                while index < blocks.count {
                    let nextBlock = blocks[index]
                    if detectStandaloneEmojiHeader(from: nextBlock) != nil { break }
                    if case .thematicBreak = nextBlock.type { break }
                    if case .heading = nextBlock.type { break }
                    contentBlocks.append(nextBlock)
                    index += 1
                }
                groups.append(.semanticBlock(type: emojiHeader.type, title: emojiHeader.title, contentBlocks: contentBlocks))
                continue
            }
            
            if isTextBlock(block) {
                currentTextBlocks.append(block)
            } else {
                if !currentTextBlocks.isEmpty {
                    groups.append(.textGroup(currentTextBlocks))
                    currentTextBlocks = []
                }
                groups.append(.specialBlock(block))
            }
            index += 1
        }

        if !currentImageRow.isEmpty {
            groups.append(.imageRow(currentImageRow))
        }
        if !currentTextBlocks.isEmpty {
            groups.append(.textGroup(currentTextBlocks))
        }

        return groups
    }
    
    private func detectStandaloneEmojiHeader(from block: MarkdownBlock) -> (type: SemanticBlockType, title: String?)? {
        let content: MarkdownInlineContent
        switch block.type {
        case .paragraph(let c): content = c
        case .heading(let c, _): content = c
        default: return nil
        }
        let text = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = EmojiSemanticPatterns.detectHeader(in: text) else { return nil }
        return (result.type, result.title)
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
            // Paragraphs with images or emoji patterns need special rendering
            if content.containsImages { return false }
            if detectEmojiSemanticType(from: content) != nil { return false }
            return true
        case .heading, .blockQuote, .list, .thematicBreak, .footnoteReference, .footnoteDefinition:
            return true
        case .codeBlock, .mermaidDiagram, .mathBlock, .table, .image, .htmlBlock:
            return false
        }
    }
    
    private func detectEmojiSemanticType(from content: MarkdownInlineContent) -> (type: SemanticBlockType, strippedContent: String)? {
        let text = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = EmojiSemanticPatterns.detect(in: text), !result.content.isEmpty else { return nil }
        return (result.type, result.content)
    }
}

// MARK: - Block Group

private enum BlockGroup {
    case textGroup([MarkdownBlock])
    case specialBlock(MarkdownBlock)
    case imageRow([(url: String, alt: String?, linkURL: String?)])
    case semanticBlock(type: SemanticBlockType, title: String?, contentBlocks: [MarkdownBlock])
}

// MARK: - Combined Text Block View

/// Renders multiple text blocks using NSTextView for stable layout and selection
struct CombinedTextBlockView: View {
    let blocks: [MarkdownBlock]

    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing
    
    private let theme = MarkdownThemeProvider()

    private func chatFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if chatFontFamily == "System Font" {
            return NSFont.systemFont(ofSize: size, weight: weight)
        } else {
            if let font = NSFont(name: chatFontFamily, size: size) {
                return weight == .regular ? font : NSFontManager.shared.convert(font, toHaveTrait: weight == .bold ? .boldFontMask : [])
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    var body: some View {
        CombinedSelectableTextView(attributedText: buildAttributedText())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let fontSize = CGFloat(chatFontSize)

        for (index, block) in blocks.enumerated() {
            if index == 0, case .heading = block.type {
                result.append(spacerLine(height: blockSpacing * 0.75))
            }
            if index > 0 {
                // Smart spacing based on previous and current block types
                let prevBlock = blocks[index - 1]
                let spacing = spacingBetween(prev: prevBlock.type, current: block.type)
                result.append(spacing)
            }

            switch block.type {
            case .paragraph(let content):
                result.append(content.themedNSAttributedString(
                    baseFont: chatFont(size: fontSize),
                    baseColor: .labelColor,
                    theme: theme
                ))

            case .heading(let content, let level):
                result.append(content.themedNSAttributedString(
                    baseFont: fontForHeading(level: level, baseSize: fontSize),
                    baseColor: .labelColor,
                    theme: theme
                ))

            case .blockQuote(let nestedBlocks):
                result.append(buildQuoteAttributedString(nestedBlocks, fontSize: fontSize))

            case .list(let items, _, _):
                result.append(buildListAttributedString(items, fontSize: fontSize))

            case .thematicBreak:
                let hr = NSAttributedString(
                    string: "───────────────────────────────",
                    attributes: [
                        .font: chatFont(size: fontSize),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                result.append(hr)

            case .footnoteReference(let id):
                let fn = NSAttributedString(
                    string: "[\(id)]",
                    attributes: [
                        .font: chatFont(size: fontSize * 0.85),
                        .foregroundColor: NSColor.controlAccentColor,
                        .baselineOffset: 4
                    ]
                )
                result.append(fn)

            case .footnoteDefinition(let id, let defBlocks):
                let fnDef = NSAttributedString(
                    string: "[\(id)]: ",
                    attributes: [
                        .font: chatFont(size: fontSize - 1),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                result.append(fnDef)
                for defBlock in defBlocks {
                    if case .paragraph(let content) = defBlock.type {
                        let contentAttr = content.themedNSAttributedString(
                            baseFont: chatFont(size: fontSize - 1),
                            baseColor: .secondaryLabelColor,
                            theme: theme
                        )
                        result.append(contentAttr)
                    }
                }

            default:
                break
            }
        }

        return result
    }

    private func fontForHeading(level: Int, baseSize: CGFloat) -> NSFont {
        switch level {
        case 1: return chatFont(size: baseSize * 1.5, weight: .bold)
        case 2: return chatFont(size: baseSize * 1.3, weight: .bold)
        case 3: return chatFont(size: baseSize * 1.15, weight: .semibold)
        case 4: return chatFont(size: baseSize * 1.05, weight: .semibold)
        default: return chatFont(size: baseSize, weight: .medium)
        }
    }

    private func buildQuoteAttributedString(_ blocks: [MarkdownBlock], fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "│ ",
            attributes: [
                .font: chatFont(size: fontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        for block in blocks {
            if case .paragraph(let content) = block.type {
                let base = chatFont(size: fontSize)
                let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
                let contentAttr = content.themedNSAttributedString(
                    baseFont: italic,
                    baseColor: .secondaryLabelColor,
                    theme: theme
                )
                result.append(contentAttr)
            }
        }

        return result
    }

    private func buildListAttributedString(_ items: [MarkdownListItem], fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, item) in items.enumerated() {
            if index > 0 || item.depth > 0 {
                result.append(NSAttributedString(
                    string: "\n",
                    attributes: [.font: chatFont(size: fontSize)]
                ))
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

            let bulletAttr = NSAttributedString(
                string: indent + bullet,
                attributes: [
                    .font: chatFont(size: fontSize),
                    .foregroundColor: theme.listMarkerColor
                ]
            )
            result.append(bulletAttr)

            var contentAttr = item.content.themedNSAttributedString(
                baseFont: chatFont(size: fontSize),
                baseColor: .labelColor,
                theme: theme
            )
            if item.checkbox == .checked {
                let mutable = NSMutableAttributedString(attributedString: contentAttr)
                mutable.addAttributes(
                    [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: NSRange(location: 0, length: mutable.length)
                )
                contentAttr = mutable
            }
            result.append(contentAttr)

            if !item.children.isEmpty {
                result.append(buildListAttributedString(item.children, fontSize: fontSize))
            }
        }

        return result
    }

    /// Determine spacing between blocks based on their types
    private func spacingBetween(prev: MarkdownBlockType, current: MarkdownBlockType) -> NSAttributedString {
        let fontSize = CGFloat(chatFontSize)
        let spacing = NSMutableAttributedString(
            string: "\n",
            attributes: [.font: chatFont(size: fontSize)]
        )

        var extra: CGFloat = blockSpacing * 0.5
        let prevIsHeading = {
            if case .heading = prev { return true }
            return false
        }()
        let currentIsHeading = {
            if case .heading = current { return true }
            return false
        }()

        if prevIsHeading {
            extra = max(extra, blockSpacing * 0.6)
        }

        if currentIsHeading {
            extra = max(extra, blockSpacing * 0.6)
        }

        switch prev {
        case .list, .blockQuote, .thematicBreak:
            extra = max(extra, blockSpacing * 0.6)
        default:
            break
        }

        switch current {
        case .list, .blockQuote, .thematicBreak:
            extra = max(extra, blockSpacing * 0.6)
        default:
            break
        }

        if extra > 0 {
            spacing.append(spacerLine(height: extra))
        }

        return spacing
    }

    private func spacerLine(height: CGFloat) -> NSAttributedString {
        return NSAttributedString(
            string: "\n",
            attributes: [.font: NSFont.systemFont(ofSize: height)]
        )
    }
}

// MARK: - Special Block Renderer

struct SpecialBlockRenderer: View {
    let block: MarkdownBlock
    var isStreaming: Bool = false
    var basePath: String? = nil
    
    private func detectEmojiSemanticType(from content: MarkdownInlineContent) -> (type: SemanticBlockType, strippedContent: String)? {
        let text = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = EmojiSemanticPatterns.detect(in: text), !result.content.isEmpty else { return nil }
        return (result.type, result.content)
    }

    var body: some View {
        switch block.type {
        case .paragraph(let content):
            if let semantic = detectEmojiSemanticType(from: content) {
                SemanticBlockView(type: semantic.type, content: semantic.strippedContent)
                    .padding(.vertical, 2)
            } else {
                MixedContentParagraphView(content: content, basePath: basePath)
                    .padding(.vertical, 2)
            }

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
            ScrollView(.horizontal, showsIndicators: false) {
                TableBlockView(rows: rows, alignments: alignments)
            }
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

// MARK: - Semantic Block With Content View

struct SemanticBlockWithContentView: View {
    let type: SemanticBlockType
    let title: String?
    let contentBlocks: [MarkdownBlock]
    var isStreaming: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(type.accentColor)
                
                Text(title ?? type.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(type.accentColor)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            if !contentBlocks.isEmpty {
                VStack(alignment: .leading, spacing: blockSpacing * 0.5) {
                    ForEach(Array(contentBlocks.enumerated()), id: \.offset) { index, block in
                        let isLast = index == contentBlocks.count - 1
                        BlockRenderer(block: block, isStreaming: isStreaming && isLast)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 4)
            }
        }
        .background(type.backgroundColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(type.borderColor(for: colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Streaming Text View

/// Optimized text view for streaming content with smooth character appearance
struct StreamingTextView: View {
    let text: String
    var allowSelection: Bool = true

    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize

    private var chatFont: Font {
        chatFontFamily == "System Font" ? .system(size: chatFontSize) : .custom(chatFontFamily, size: chatFontSize)
    }

    var body: some View {
        if allowSelection {
            Text(text)
                .font(chatFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(chatFont)
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
    private let streamingIntervalNanos: UInt64 = 8_000_000
    private let streamingLargeIntervalNanos: UInt64 = 16_000_000
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

    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing

    private var chatFont: Font {
        if chatFontFamily == "System Font" {
            return .system(size: chatFontSize)
        } else {
            return .custom(chatFontFamily, size: chatFontSize)
        }
    }

    private func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if chatFontFamily == "System Font" {
            return NSFont.systemFont(ofSize: size, weight: weight)
        } else if let font = NSFont(name: chatFontFamily, size: size) {
            return weight == .regular ? font : NSFontManager.shared.convert(font, toHaveTrait: weight == .bold ? .boldFontMask : [])
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    var body: some View {
        switch block.type {
        case .paragraph(let content):
            // Check if paragraph contains images - render as mixed content if so
            if content.containsImages {
                MixedContentParagraphView(content: content)
                    .padding(.vertical, blockSpacing * 0.25)
            } else {
                SelectableTextView(
                    content: content,
                    baseFont: nsFont(size: CGFloat(chatFontSize)),
                    baseColor: .labelColor
                )
                .padding(.vertical, blockSpacing * 0.25)
            }

        case .heading(let content, let level):
            SelectableTextView(
                content: content,
                baseFont: fontForHeading(level: level),
                baseColor: .labelColor
            )
            .fontWeight(level <= 2 ? .bold : .semibold)
            .padding(.top, level <= 2 ? blockSpacing : blockSpacing * 0.5)
            .padding(.bottom, blockSpacing * 0.25)

        case .codeBlock(let code, let language, _):
            if language?.lowercased() == "mermaid" {
                MermaidDiagramView(code: code, isStreaming: isStreaming)
                    .padding(.vertical, blockSpacing * 0.5)
            } else {
                CodeBlockView(
                    code: code,
                    language: language,
                    isStreaming: isStreaming
                )
                .padding(.vertical, blockSpacing * 0.5)
            }

        case .mermaidDiagram(let code):
            MermaidDiagramView(code: code, isStreaming: isStreaming)
                .padding(.vertical, blockSpacing * 0.5)

        case .mathBlock(let content):
            MathBlockView(content: content, isBlock: true)
                .padding(.vertical, blockSpacing)

        case .list(let items, _, _):
            ListBlockView(items: items)
                .padding(.vertical, blockSpacing * 0.25)

        case .blockQuote(let blocks):
            BlockQuoteView(blocks: blocks, isStreaming: isStreaming)
                .padding(.vertical, blockSpacing * 0.5)

        case .table(let rows, let alignments):
            ScrollView(.horizontal, showsIndicators: false) {
                TableBlockView(rows: rows, alignments: alignments)
            }
            .padding(.vertical, blockSpacing * 0.5)

        case .image(let url, let alt):
            MarkdownImageView(url: url, alt: alt)
                .padding(.vertical, blockSpacing * 0.5)

        case .thematicBreak:
            Divider()
                .padding(.vertical, blockSpacing)

        case .htmlBlock(let html):
            SelectableTextView(
                content: MarkdownInlineContent(text: html),
                baseFont: .monospacedSystemFont(ofSize: CGFloat(chatFontSize), weight: .regular),
                baseColor: .secondaryLabelColor
            )
            .padding(.vertical, blockSpacing * 0.25)

        case .footnoteReference(let id):
            Text("[\(id)]")
                .font(chatFontFamily == "System Font" ? .system(size: chatFontSize * 0.85) : .custom(chatFontFamily, size: chatFontSize * 0.85))
                .foregroundColor(.blue)
                .baselineOffset(4)

        case .footnoteDefinition(let id, let blocks):
            VStack(alignment: .leading, spacing: blockSpacing * 0.25) {
                Text("[\(id)]:")
                    .font(chatFontFamily == "System Font" ? .system(size: chatFontSize * 0.85) : .custom(chatFontFamily, size: chatFontSize * 0.85))
                    .foregroundColor(.secondary)
                ForEach(blocks) { nestedBlock in
                    BlockRenderer(block: nestedBlock, isStreaming: false)
                }
            }
            .padding(.leading, 16)
        }
    }

    private func fontForHeading(level: Int) -> NSFont {
        let baseSize = CGFloat(chatFontSize)
        switch level {
        case 1: return nsFont(size: baseSize * 1.5, weight: .bold)
        case 2: return nsFont(size: baseSize * 1.3, weight: .bold)
        case 3: return nsFont(size: baseSize * 1.15, weight: .semibold)
        case 4: return nsFont(size: baseSize * 1.05, weight: .semibold)
        default: return nsFont(size: baseSize, weight: .medium)
        }
    }
}

// MARK: - Mixed Content Paragraph View

/// Renders paragraphs that contain images mixed with text
struct MixedContentParagraphView: View {
    let content: MarkdownInlineContent
    var basePath: String? = nil

    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing

    private func nsFont(size: CGFloat) -> NSFont {
        if chatFontFamily == "System Font" {
            return NSFont.systemFont(ofSize: size)
        } else if let font = NSFont(name: chatFontFamily, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }

    var body: some View {
        let segments = splitIntoSegments(content.elements)

        // Check if all segments are images (badge row)
        let allImages = segments.allSatisfy { if case .image = $0 { return true } else { return false } }

        if allImages && segments.count > 1 {
            // Render as horizontal row of badges with wrapping
            FlowLayout(spacing: blockSpacing * 0.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if case .image(let url, let alt, let linkURL) = segment {
                        LinkedImageView(url: url, alt: alt, linkURL: linkURL, basePath: basePath)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: blockSpacing * 0.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let elements):
                        if !elements.isEmpty {
                            SelectableTextView(
                                content: MarkdownInlineContent(elements: elements),
                                baseFont: nsFont(size: CGFloat(chatFontSize)),
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
    var theme: MarkdownThemeProvider = MarkdownThemeProvider()

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
        let attributed = content.themedNSAttributedString(baseFont: baseFont, baseColor: baseColor, theme: theme)
        if textView.attributedString() != attributed {
            textView.textStorage?.setAttributedString(attributed)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FixedTextView, context: Context) -> CGSize? {
        guard let layoutManager = nsView.layoutManager,
              let container = nsView.textContainer else {
            return nil
        }

        // Use proposed width, fallback to reasonable default for text readability
        let width = proposal.width ?? 800
        container.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)

        let rect = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: max(rect.height + 2, 16))
    }
}

/// NSTextView-based text view for combined attributed markdown blocks
struct CombinedSelectableTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

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
        if !textView.attributedString().isEqual(to: attributedText) {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FixedTextView, context: Context) -> CGSize? {
        guard let layoutManager = nsView.layoutManager,
              let container = nsView.textContainer else {
            return nil
        }

        // Use proposed width, fallback to reasonable default for text readability
        let width = proposal.width ?? 800
        container.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)

        let rect = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: max(rect.height + 2, 16))
    }
}

// MARK: - List Block View

struct ListBlockView: View {
    let items: [MarkdownListItem]

    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing

    var body: some View {
        VStack(alignment: .leading, spacing: blockSpacing * 0.25) {
            ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                ListItemView(item: item)
            }
        }
    }
}

struct ListItemView: View {
    let item: MarkdownListItem

    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing

    private let theme = MarkdownThemeProvider()
    
    private var chatFont: Font {
        chatFontFamily == "System Font" ? .system(size: chatFontSize) : .custom(chatFontFamily, size: chatFontSize)
    }

    private func nsFont(size: CGFloat) -> NSFont {
        if chatFontFamily == "System Font" {
            return NSFont.systemFont(ofSize: size)
        } else if let font = NSFont(name: chatFontFamily, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }
    
    private var markerColor: Color {
        Color(nsColor: theme.listMarkerColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: blockSpacing * 0.25) {
            HStack(alignment: .top, spacing: 6) {
                if item.depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(item.depth) * 16)
                }

                if let checkbox = item.checkbox {
                    Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checkbox == .checked ? .green : markerColor)
                        .font(chatFont)
                        .frame(width: 16)
                } else if item.listOrdered {
                    Text("\(item.listStartIndex + item.itemIndex).")
                        .foregroundStyle(markerColor)
                        .font(chatFont)
                        .frame(minWidth: 16, alignment: .trailing)
                } else {
                    Text(bulletForDepth(item.depth))
                        .foregroundStyle(markerColor)
                        .font(chatFont)
                        .frame(width: 16)
                }

                // Content
                SelectableTextView(
                    content: item.content,
                    baseFont: nsFont(size: CGFloat(chatFontSize)),
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

    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing
    @Environment(\.colorScheme) private var colorScheme
    
    private var detectedAdmonition: (type: SemanticBlockType, title: String?)? {
        guard let firstBlock = blocks.first,
              case .paragraph(let content) = firstBlock.type else {
            return nil
        }
        
        let text = content.plainText
        let patterns: [(prefix: String, type: SemanticBlockType, title: String)] = [
            ("[!NOTE]", .note, "Note"),
            ("[!TIP]", .info, "Tip"),
            ("[!INFO]", .info, "Info"),
            ("[!IMPORTANT]", .warning, "Important"),
            ("[!WARNING]", .warning, "Warning"),
            ("[!CAUTION]", .warning, "Caution"),
            ("[!ERROR]", .error, "Error"),
            ("[!DANGER]", .error, "Danger"),
            ("[!SUCCESS]", .success, "Success"),
            ("**Note:**", .note, "Note"),
            ("**Tip:**", .info, "Tip"),
            ("**Info:**", .info, "Info"),
            ("**Warning:**", .warning, "Warning"),
            ("**Important:**", .warning, "Important"),
            ("**Error:**", .error, "Error"),
            ("**Success:**", .success, "Success"),
        ]
        
        for (prefix, type, title) in patterns {
            if text.hasPrefix(prefix) {
                return (type, title)
            }
        }
        return nil
    }

    var body: some View {
        if let admonition = detectedAdmonition {
            admonitionView(type: admonition.type, title: admonition.title)
        } else {
            standardBlockQuote
        }
    }
    
    private var standardBlockQuote: some View {
        HStack(alignment: .top, spacing: blockSpacing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: blockSpacing * 0.5) {
                ForEach(blocks) { block in
                    BlockRenderer(block: block, isStreaming: isStreaming)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func admonitionView(type: SemanticBlockType, title: String?) -> some View {
        let bgColor = type.backgroundColor(for: colorScheme)
        let borderColor = type.borderColor(for: colorScheme)
        
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(type.accentColor)
                
                Text(title ?? type.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(type.accentColor)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: blockSpacing * 0.5) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    if index == 0, case .paragraph(let content) = block.type {
                        let strippedContent = stripAdmonitionPrefix(content)
                        if !strippedContent.elements.isEmpty {
                            SelectableTextView(
                                content: strippedContent,
                                baseFont: NSFont.systemFont(ofSize: 12),
                                baseColor: .labelColor
                            )
                        }
                    } else {
                        BlockRenderer(block: block, isStreaming: isStreaming)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 4)
        }
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private func stripAdmonitionPrefix(_ content: MarkdownInlineContent) -> MarkdownInlineContent {
        let prefixes = [
            "[!NOTE]", "[!TIP]", "[!INFO]", "[!IMPORTANT]", "[!WARNING]",
            "[!CAUTION]", "[!ERROR]", "[!DANGER]", "[!SUCCESS]",
            "**Note:**", "**Tip:**", "**Info:**", "**Warning:**",
            "**Important:**", "**Error:**", "**Success:**"
        ]
        
        var elements = content.elements
        guard !elements.isEmpty else { return content }
        
        if case .text(var text) = elements[0] {
            for prefix in prefixes {
                if text.hasPrefix(prefix) {
                    text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if text.isEmpty {
                        elements.removeFirst()
                    } else {
                        elements[0] = .text(text)
                    }
                    break
                }
            }
        }
        
        if !elements.isEmpty, case .strong(let innerContent) = elements[0] {
            let strongText = innerContent.plainText
            
            let strongPrefixes = ["Note:", "Tip:", "Info:", "Warning:", "Important:", "Error:", "Success:"]
            for prefix in strongPrefixes {
                if strongText == prefix || strongText.hasPrefix(prefix) {
                    elements.removeFirst()
                    if elements.first != nil, case .text(var nextText) = elements.first {
                        nextText = nextText.trimmingCharacters(in: .whitespaces)
                        if nextText.isEmpty {
                            elements.removeFirst()
                        } else {
                            elements[0] = .text(nextText)
                        }
                    }
                    break
                }
            }
        }
        
        return MarkdownInlineContent(elements: elements)
    }
}

// MARK: - Table Block View

struct TableBlockView: View {
    let rows: [MarkdownTableRow]
    let alignments: [ColumnAlignment]

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize

    private var chatFont: Font {
        chatFontFamily == "System Font" ? .system(size: chatFontSize) : .custom(chatFontFamily, size: chatFontSize)
    }

    private var chatFontBold: Font {
        chatFontFamily == "System Font" ? .system(size: chatFontSize, weight: .semibold) : .custom(chatFontFamily, size: chatFontSize).weight(.semibold)
    }

    private func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if chatFontFamily == "System Font" {
            return NSFont.systemFont(ofSize: size, weight: weight)
        } else if let font = NSFont(name: chatFontFamily, size: size) {
            return weight == .regular ? font : NSFontManager.shared.convert(font, toHaveTrait: weight == .bold ? .boldFontMask : [])
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

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
        let fontSize = CGFloat(chatFontSize)

        var widths: [CGFloat] = Array(repeating: 40, count: columnCount) // minimum width

        for row in rows {
            for (index, cell) in row.cells.enumerated() where index < columnCount {
                // Estimate width based on content length
                let text = cell.plainText
                let font = row.isHeader
                    ? nsFont(size: fontSize, weight: .semibold)
                    : nsFont(size: fontSize)
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
                                .font(row.isHeader ? chatFontBold : chatFont)
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
