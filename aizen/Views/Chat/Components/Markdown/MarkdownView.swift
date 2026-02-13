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
import CodeEditSourceEditor

private enum MarkdownInlineCodeTheme {
    static func inlineCodeColor(
        colorScheme: ColorScheme,
        terminalThemeName: String,
        terminalThemeNameLight: String,
        usePerAppearanceTheme: Bool
    ) -> NSColor {
        let effectiveThemeName: String
        if usePerAppearanceTheme {
            effectiveThemeName = colorScheme == .dark ? terminalThemeName : terminalThemeNameLight
        } else {
            effectiveThemeName = terminalThemeName
        }

        if let theme = GhosttyThemeParser.loadTheme(named: effectiveThemeName) {
            // Cursor/insertion-point color is the closest thing to a theme accent.
            return theme.insertionPoint
        }

        return NSColor.controlAccentColor
    }
}

// MARK: - Fixed Text View

/// NSTextView subclass that doesn't trigger layout updates during drawing
final class FixedTextView: NSTextView {}

// MARK: - Markdown View

/// Main markdown renderer with cross-block text selection support
struct MarkdownView: View {
    let content: String
    var isStreaming: Bool = false
    var basePath: String? = nil  // Base path for resolving relative URLs (e.g., directory of markdown file)
    var onOpenFileInEditor: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing
    @StateObject private var viewModel = MarkdownViewModel()

    var body: some View {
        let blockTransition: AnyTransition = isStreaming ? .identity : .opacity

        VStack(alignment: .leading, spacing: blockSpacing) {
            // Group consecutive text blocks for cross-block selection
            let groups = groupBlocks(viewModel.blocks)

            ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                switch group {
                case .textGroup(let blocks):
                    // Render multiple text blocks in a single selectable view
                    CombinedTextBlockView(
                        blocks: blocks,
                        basePath: basePath,
                        onOpenFileInEditor: onOpenFileInEditor
                    )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                        .transition(blockTransition)

                case .specialBlock(let block):
                    // Render special blocks separately
                    let isLastBlock = groupIndex == groups.count - 1
                    SpecialBlockRenderer(
                        block: block,
                        isStreaming: isStreaming && isLastBlock,
                        basePath: basePath,
                        onOpenFileInEditor: onOpenFileInEditor
                    )
                    .transition(blockTransition)

                case .imageRow(let images):
                    // Render consecutive images in a flow layout (wraps to new lines)
                    FlowLayout(spacing: 4) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                            LinkedImageView(url: img.url, alt: img.alt, linkURL: img.linkURL, basePath: basePath)
                        }
                    }
                    .padding(.vertical, 2)
                    .transition(blockTransition)
                }
            }

            // Streaming buffer (incomplete content)
            if isStreaming && !viewModel.streamingBuffer.isEmpty {
                StreamingTextView(text: viewModel.streamingBuffer, allowSelection: false)
                    .padding(.vertical, 2)
                    .transition(blockTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .onChange(of: content) { _, newContent in
            viewModel.parse(newContent, isStreaming: isStreaming)
        }
        .onChange(of: isStreaming) { _, newIsStreaming in
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

/// Renders multiple text blocks using NSTextView for stable layout and selection
struct CombinedTextBlockView: View {
    let blocks: [MarkdownBlock]
    var basePath: String? = nil
    var onOpenFileInEditor: ((String) -> Void)? = nil

    @AppStorage(ChatSettings.fontFamilyKey) private var chatFontFamily = ChatSettings.defaultFontFamily
    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @AppStorage(ChatSettings.blockSpacingKey) private var blockSpacing = ChatSettings.defaultBlockSpacing
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalThemeNameLight") private var terminalThemeNameLight = "Aizen Light"
    @AppStorage("terminalUsePerAppearanceTheme") private var terminalUsePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    private var inlineCodeColor: NSColor {
        MarkdownInlineCodeTheme.inlineCodeColor(
            colorScheme: colorScheme,
            terminalThemeName: terminalThemeName,
            terminalThemeNameLight: terminalThemeNameLight,
            usePerAppearanceTheme: terminalUsePerAppearanceTheme
        )
    }
    @StateObject private var textCache = CombinedTextLayoutCache()

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
        let resolved = textCache.resolve(key: renderKey) { buildAttributedText() }
        CombinedSelectableTextView(
            attributedText: resolved.text,
            revision: resolved.revision,
            basePath: basePath,
            onOpenFileInEditor: onOpenFileInEditor
        )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderKey: Int {
        var hasher = Hasher()
        hasher.combine(chatFontFamily)
        hasher.combine(chatFontSize)
        hasher.combine(blockSpacing)
        hasher.combine(terminalThemeName)
        hasher.combine(terminalThemeNameLight)
        hasher.combine(terminalUsePerAppearanceTheme)
        hasher.combine(String(describing: colorScheme))
        hasher.combine(basePath ?? "")
        hasher.combine(blocks.count)
        for block in blocks {
            hasher.combine(block.id)
            hasher.combine(String(describing: block.type))
        }
        return hasher.finalize()
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
                result.append(content.nsAttributedString(
                    baseFont: chatFont(size: fontSize),
                    baseColor: .labelColor,
                    inlineCodeColor: inlineCodeColor,
                    basePath: basePath
                ))

            case .heading(let content, let level):
                result.append(content.nsAttributedString(
                    baseFont: fontForHeading(level: level, baseSize: fontSize),
                    baseColor: .labelColor,
                    inlineCodeColor: inlineCodeColor,
                    basePath: basePath
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
                        let contentAttr = content.nsAttributedString(
                            baseFont: chatFont(size: fontSize - 1),
                            baseColor: .secondaryLabelColor,
                            inlineCodeColor: inlineCodeColor,
                            basePath: basePath
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
                let contentAttr = content.nsAttributedString(
                    baseFont: italic,
                    baseColor: .secondaryLabelColor,
                    inlineCodeColor: inlineCodeColor,
                    basePath: basePath
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
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            result.append(bulletAttr)

            var contentAttr = item.content.nsAttributedString(
                baseFont: chatFont(size: fontSize),
                baseColor: .labelColor,
                inlineCodeColor: inlineCodeColor,
                basePath: basePath
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

@MainActor
private final class CombinedTextLayoutCache: ObservableObject {
    private var currentKey: Int?
    private var currentText: NSAttributedString = NSAttributedString(string: "")
    private var currentRevision: UInt64 = 0

    func resolve(key: Int, build: () -> NSAttributedString) -> (text: NSAttributedString, revision: UInt64) {
        guard currentKey != key else {
            return (currentText, currentRevision)
        }

        currentKey = key
        currentText = build()
        currentRevision &+= 1
        return (currentText, currentRevision)
    }
}

// MARK: - Special Block Renderer

/// Renders blocks that need special handling (code, mermaid, math, tables, images, paragraphs with images)
struct SpecialBlockRenderer: View {
    let block: MarkdownBlock
    var isStreaming: Bool = false
    var basePath: String? = nil
    var onOpenFileInEditor: ((String) -> Void)? = nil

    var body: some View {
        switch block.type {
        case .paragraph(let content):
            // Paragraph with images
            MixedContentParagraphView(
                content: content,
                basePath: basePath,
                onOpenFileInEditor: onOpenFileInEditor
            )
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
            HorizontalOnlyScrollView(showsIndicators: false) {
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

                let (contentSnapshot, isStreamingSnapshot, interval, lastParsedLength) = await MainActor.run { [weak self] in
                    guard let self else { return ("", false, UInt64(0), 0) }
                    let interval = self.pendingContent.count > self.streamingLargeContentThreshold
                        ? self.streamingLargeIntervalNanos
                        : self.streamingIntervalNanos
                    return (self.pendingContent, self.pendingIsStreaming, interval, self.lastParsedLength)
                }

                if contentSnapshot.count != lastParsedLength {
                    let parser = MarkdownParser()
                    let document = parser.parseStreaming(contentSnapshot, isComplete: false)
                    await MainActor.run { [weak self] in
                        guard let self, generation == self.parseGeneration else { return }
                        self.blocks = document.blocks
                        self.streamingBuffer = document.streamingBuffer
                        self.lastParsedLength = contentSnapshot.count
                    }
                }

                if !isStreamingSnapshot {
                    break
                }

                let sleepInterval = (contentSnapshot.count == lastParsedLength)
                    ? max(interval, 32_000_000)
                    : interval
                try? await Task.sleep(nanoseconds: sleepInterval)
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
            HorizontalOnlyScrollView(showsIndicators: false) {
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
    var onOpenFileInEditor: ((String) -> Void)? = nil

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
                                baseColor: .labelColor,
                                basePath: basePath,
                                onOpenFileInEditor: onOpenFileInEditor
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
    var basePath: String? = nil
    var onOpenFileInEditor: ((String) -> Void)? = nil
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalThemeNameLight") private var terminalThemeNameLight = "Aizen Light"
    @AppStorage("terminalUsePerAppearanceTheme") private var terminalUsePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    private var inlineCodeColor: NSColor {
        MarkdownInlineCodeTheme.inlineCodeColor(
            colorScheme: colorScheme,
            terminalThemeName: terminalThemeName,
            terminalThemeNameLight: terminalThemeNameLight,
            usePerAppearanceTheme: terminalUsePerAppearanceTheme
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var renderKey: Int?
        var measuredRenderKey: Int?
        var measuredWidth: CGFloat?
        var measuredSize: CGSize?
        var basePath: String?
        var onOpenFileInEditor: ((String) -> Void)?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = linkURL(from: link),
                  let destination = MarkdownLocalPathResolver.existingDestinationPath(from: url, basePath: basePath) else {
                return false
            }

            if let onOpenFileInEditor {
                onOpenFileInEditor(destination)
            } else {
                NotificationCenter.default.post(
                    name: .openFileInEditor,
                    object: nil,
                    userInfo: ["path": destination]
                )
            }
            return true
        }

        private func linkURL(from link: Any) -> URL? {
            if let url = link as? URL {
                return url
            }
            if let string = link as? String {
                return URL(string: string)
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FixedTextView {
        let textView = FixedTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        if let container = textView.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            container.heightTracksTextView = false
        }
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.usesFindBar = false
        textView.isRichText = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: FixedTextView, context: Context) {
        context.coordinator.basePath = basePath
        context.coordinator.onOpenFileInEditor = onOpenFileInEditor

        let key = makeRenderKey()
        guard context.coordinator.renderKey != key else { return }
        context.coordinator.renderKey = key
        context.coordinator.measuredRenderKey = nil
        context.coordinator.measuredWidth = nil
        context.coordinator.measuredSize = nil
        textView.textStorage?.setAttributedString(
            content.nsAttributedString(
                baseFont: baseFont,
                baseColor: baseColor,
                inlineCodeColor: inlineCodeColor,
                basePath: basePath
            )
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FixedTextView, context: Context) -> CGSize? {
        guard let layoutManager = nsView.layoutManager,
              let container = nsView.textContainer else {
            return nil
        }

        // Use proposed width, fallback to reasonable default for text readability
        let proposedWidth = proposal.width ?? nsView.bounds.width
        let width = max((proposedWidth > 0 ? proposedWidth : 800).rounded(.towardZero), 1)
        let key = context.coordinator.renderKey ?? makeRenderKey()
        if context.coordinator.measuredRenderKey == key,
           let cachedWidth = context.coordinator.measuredWidth,
           abs(cachedWidth - width) < 0.5,
           let cachedSize = context.coordinator.measuredSize {
            return cachedSize
        }

        container.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)

        let rect = layoutManager.usedRect(for: container)
        let measuredSize = CGSize(width: width, height: max(rect.height + 2, 16))
        context.coordinator.measuredRenderKey = key
        context.coordinator.measuredWidth = width
        context.coordinator.measuredSize = measuredSize
        return measuredSize
    }

    private func makeRenderKey() -> Int {
        var hasher = Hasher()
        hasher.combine(content.elements)
        hasher.combine(baseFont.fontName)
        hasher.combine(baseFont.pointSize)
        combineColor(baseColor, into: &hasher)
        combineColor(inlineCodeColor, into: &hasher)
        hasher.combine(basePath ?? "")
        hasher.combine(terminalThemeName)
        hasher.combine(terminalThemeNameLight)
        hasher.combine(terminalUsePerAppearanceTheme)
        hasher.combine(String(describing: colorScheme))
        return hasher.finalize()
    }

    private func combineColor(_ color: NSColor, into hasher: inout Hasher) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        hasher.combine(converted.redComponent)
        hasher.combine(converted.greenComponent)
        hasher.combine(converted.blueComponent)
        hasher.combine(converted.alphaComponent)
    }
}

/// NSTextView-based text view for combined attributed markdown blocks
struct CombinedSelectableTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    let revision: UInt64
    var basePath: String? = nil
    var onOpenFileInEditor: ((String) -> Void)? = nil

    final class Coordinator: NSObject, NSTextViewDelegate {
        var revision: UInt64 = .max
        var measuredRevision: UInt64 = .max
        var measuredWidth: CGFloat?
        var measuredSize: CGSize?
        var basePath: String?
        var onOpenFileInEditor: ((String) -> Void)?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = linkURL(from: link),
                  let destination = MarkdownLocalPathResolver.existingDestinationPath(from: url, basePath: basePath) else {
                return false
            }

            if let onOpenFileInEditor {
                onOpenFileInEditor(destination)
            } else {
                NotificationCenter.default.post(
                    name: .openFileInEditor,
                    object: nil,
                    userInfo: ["path": destination]
                )
            }
            return true
        }

        private func linkURL(from link: Any) -> URL? {
            if let url = link as? URL {
                return url
            }
            if let string = link as? String {
                return URL(string: string)
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FixedTextView {
        let textView = FixedTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        if let container = textView.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            container.heightTracksTextView = false
        }
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.usesFindBar = false
        textView.isRichText = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: FixedTextView, context: Context) {
        context.coordinator.basePath = basePath
        context.coordinator.onOpenFileInEditor = onOpenFileInEditor

        guard context.coordinator.revision != revision else { return }
        context.coordinator.revision = revision
        context.coordinator.measuredRevision = .max
        context.coordinator.measuredWidth = nil
        context.coordinator.measuredSize = nil
        textView.textStorage?.setAttributedString(attributedText)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FixedTextView, context: Context) -> CGSize? {
        guard let layoutManager = nsView.layoutManager,
              let container = nsView.textContainer else {
            return nil
        }

        // Use proposed width, fallback to reasonable default for text readability
        let proposedWidth = proposal.width ?? nsView.bounds.width
        let width = max((proposedWidth > 0 ? proposedWidth : 800).rounded(.towardZero), 1)
        if context.coordinator.measuredRevision == revision,
           let cachedWidth = context.coordinator.measuredWidth,
           abs(cachedWidth - width) < 0.5,
           let cachedSize = context.coordinator.measuredSize {
            return cachedSize
        }

        container.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)

        let rect = layoutManager.usedRect(for: container)
        let measuredSize = CGSize(width: width, height: max(rect.height + 2, 16))
        context.coordinator.measuredRevision = revision
        context.coordinator.measuredWidth = width
        context.coordinator.measuredSize = measuredSize
        return measuredSize
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

    var body: some View {
        VStack(alignment: .leading, spacing: blockSpacing * 0.25) {
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
                        .font(chatFont)
                        .frame(width: 16)
                } else if item.listOrdered {
                    Text("\(item.listStartIndex + item.itemIndex).")
                        .foregroundStyle(.secondary)
                        .font(chatFont)
                        .frame(minWidth: 16, alignment: .trailing)
                } else {
                    Text(bulletForDepth(item.depth))
                        .foregroundStyle(.secondary)
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

    var body: some View {
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
