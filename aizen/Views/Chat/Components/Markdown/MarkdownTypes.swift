//  MarkdownTypes.swift
//  aizen
//
//  Production-ready markdown block types and parsing utilities
//

import SwiftUI
import Combine
import Markdown
import AppKit

// MARK: - Parsed Markdown Document

/// Represents a fully parsed markdown document with all blocks
nonisolated struct ParsedMarkdownDocument {
    let blocks: [MarkdownBlock]
    let footnotes: [String: MarkdownBlock]
    let isComplete: Bool
    let streamingBuffer: String

    static let empty = ParsedMarkdownDocument(blocks: [], footnotes: [:], isComplete: true, streamingBuffer: "")
}

// MARK: - Markdown Block

/// Markdown block with stable ID for efficient SwiftUI diffing
nonisolated struct MarkdownBlock: Identifiable, Equatable {
    let id: String
    let type: MarkdownBlockType

    init(_ type: MarkdownBlockType, index: Int = 0) {
        self.type = type
        self.id = Self.generateId(for: type, index: index)
    }

    private static func generateId(for type: MarkdownBlockType, index: Int) -> String {
        switch type {
        case .paragraph(let content):
            return "p-\(index)-\(content.hashValue)"
        case .heading(_, let level):
            return "h\(level)-\(index)"
        case .codeBlock(let code, let lang, _):
            return "code-\(index)-\(lang ?? "plain")-\(code.prefix(50).hashValue)"
        case .list(let items, let ordered, _):
            return "list-\(ordered)-\(index)-\(items.count)"
        case .blockQuote(let blocks):
            return "quote-\(index)-\(blocks.count)"
        case .table(let rows, _):
            return "table-\(index)-\(rows.count)"
        case .image(let url, _):
            return "img-\(index)-\(url.hashValue)"
        case .thematicBreak:
            return "hr-\(index)"
        case .htmlBlock(let html):
            return "html-\(index)-\(html.prefix(50).hashValue)"
        case .mermaidDiagram(let code):
            return "mermaid-\(index)-\(code.prefix(50).hashValue)"
        case .mathBlock(let content):
            return "math-\(index)-\(content.hashValue)"
        case .footnoteReference(let id):
            return "fnref-\(index)-\(id)"
        case .footnoteDefinition(let id, _):
            return "fndef-\(index)-\(id)"
        }
    }

    static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Markdown Block Type

nonisolated enum MarkdownBlockType: Equatable {
    case paragraph(MarkdownInlineContent)
    case heading(MarkdownInlineContent, level: Int)
    case codeBlock(code: String, language: String?, isStreaming: Bool)
    case list(items: [MarkdownListItem], ordered: Bool, startIndex: Int)
    case blockQuote(blocks: [MarkdownBlock])
    case table(rows: [MarkdownTableRow], alignments: [ColumnAlignment])
    case image(url: String, alt: String?)
    case thematicBreak
    case htmlBlock(String)
    case mermaidDiagram(String)
    case mathBlock(String)
    case footnoteReference(id: String)
    case footnoteDefinition(id: String, blocks: [MarkdownBlock])

    static func == (lhs: MarkdownBlockType, rhs: MarkdownBlockType) -> Bool {
        switch (lhs, rhs) {
        case (.paragraph(let l), .paragraph(let r)): return l == r
        case (.heading(let lc, let ll), .heading(let rc, let rl)): return lc == rc && ll == rl
        case (.codeBlock(let lc, let ll, _), .codeBlock(let rc, let rl, _)): return lc == rc && ll == rl
        case (.thematicBreak, .thematicBreak): return true
        case (.htmlBlock(let l), .htmlBlock(let r)): return l == r
        case (.mermaidDiagram(let l), .mermaidDiagram(let r)): return l == r
        case (.mathBlock(let l), .mathBlock(let r)): return l == r
        case (.footnoteReference(let l), .footnoteReference(let r)): return l == r
        case (.image(let lu, let la), .image(let ru, let ra)): return lu == ru && la == ra
        default: return false
        }
    }
}

// MARK: - Column Alignment

nonisolated enum ColumnAlignment: Equatable {
    case left
    case center
    case right
    case none

    init(from alignment: Markdown.Table.ColumnAlignment?) {
        switch alignment {
        case .left: self = .left
        case .center: self = .center
        case .right: self = .right
        case .none: self = .none
        }
    }
}

// MARK: - Markdown List Item

nonisolated struct MarkdownListItem: Identifiable, Equatable {
    let id: String
    let content: MarkdownInlineContent
    let children: [MarkdownListItem]
    let checkbox: CheckboxState?
    let depth: Int
    let listOrdered: Bool
    let listStartIndex: Int
    let itemIndex: Int

    enum CheckboxState: Equatable {
        case checked
        case unchecked
    }

    init(
        content: MarkdownInlineContent,
        children: [MarkdownListItem] = [],
        checkbox: CheckboxState? = nil,
        depth: Int = 0,
        index: Int = 0,
        listOrdered: Bool = false,
        listStartIndex: Int = 1
    ) {
        self.content = content
        self.children = children
        self.checkbox = checkbox
        self.depth = depth
        self.listOrdered = listOrdered
        self.listStartIndex = listStartIndex
        self.itemIndex = index
        let orderTag = listOrdered ? "o" : "u"
        self.id = "li-\(depth)-\(index)-\(orderTag)-\(content.hashValue)"
    }
}

// MARK: - Markdown Table Row

nonisolated struct MarkdownTableRow: Identifiable, Equatable {
    let id: String
    let cells: [MarkdownInlineContent]
    let isHeader: Bool

    init(cells: [MarkdownInlineContent], isHeader: Bool = false, index: Int = 0) {
        self.cells = cells
        self.isHeader = isHeader
        self.id = "row-\(isHeader ? "h" : "b")-\(index)"
    }
}

// MARK: - Markdown Inline Content

/// Rich inline content that can be rendered as AttributedString
nonisolated struct MarkdownInlineContent: Equatable, Hashable {
    let elements: [InlineElement]

    var isEmpty: Bool { elements.isEmpty }
    var plainText: String {
        elements.map { $0.plainText }.joined()
    }

    /// Check if content contains any image elements (including images inside links)
    var containsImages: Bool {
        elements.contains { element in
            switch element {
            case .image:
                return true
            case .link(let content, _, _):
                // Check if link contains an image (badge pattern: [![alt](img)](url))
                return content.containsImages
            default:
                return false
            }
        }
    }

    init(elements: [InlineElement] = []) {
        self.elements = elements
    }

    init(text: String) {
        self.elements = [.text(text)]
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(plainText)
    }
}

// MARK: - Inline Element

nonisolated enum InlineElement: Equatable, Hashable {
    case text(String)
    case emphasis(MarkdownInlineContent)
    case strong(MarkdownInlineContent)
    case strikethrough(MarkdownInlineContent)
    case code(String)
    case link(text: MarkdownInlineContent, url: String, title: String?)
    case image(url: String, alt: String?, title: String?)
    case softBreak
    case hardBreak
    case html(String)
    case math(String)
    case footnoteReference(id: String)

    var plainText: String {
        switch self {
        case .text(let t): return t
        case .emphasis(let c): return c.plainText
        case .strong(let c): return c.plainText
        case .strikethrough(let c): return c.plainText
        case .code(let c): return c
        case .link(let t, _, _): return t.plainText
        case .image(_, let alt, _): return alt ?? ""
        case .softBreak: return " "
        case .hardBreak: return "\n"
        case .html(let h): return h
        case .math(let m): return m
        case .footnoteReference(let id): return "[\(id)]"
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(plainText)
    }
}

// MARK: - Footnote Storage

class FootnoteStorage: ObservableObject {
    @Published var definitions: [String: [MarkdownBlock]] = [:]
    @Published var references: [String] = []

    func addDefinition(id: String, blocks: [MarkdownBlock]) {
        definitions[id] = blocks
    }

    func addReference(id: String) {
        if !references.contains(id) {
            references.append(id)
        }
    }

    func getIndex(for id: String) -> Int? {
        references.firstIndex(of: id).map { $0 + 1 }
    }

    func reset() {
        definitions.removeAll()
        references.removeAll()
    }
}

// MARK: - Markdown Parser

/// Production-ready markdown parser using swift-markdown AST
nonisolated final class MarkdownParser {

    struct Options {
        var parseSymbolLinks: Bool = true
        var parseBlockDirectives: Bool = false

        static let `default` = Options()
    }

    private let options: Options

    init(options: Options = .default) {
        self.options = options
    }

    /// Parse complete markdown content
    func parse(_ content: String) -> ParsedMarkdownDocument {
        guard !content.isEmpty else { return .empty }

        var parserOptions: ParseOptions = []
        if options.parseSymbolLinks { parserOptions.insert(.parseSymbolLinks) }
        if options.parseBlockDirectives { parserOptions.insert(.parseBlockDirectives) }

        var blocks: [MarkdownBlock] = []
        var footnotes: [String: MarkdownBlock] = [:]
        var index = 0

        // Extract $$...$$ math blocks first, then parse markdown segments
        let segments = extractMathBlocks(from: content)

        for segment in segments {
            if segment.isMath {
                blocks.append(MarkdownBlock(.mathBlock(segment.content), index: index))
                index += 1
            } else {
                let document = Document(parsing: segment.content, options: parserOptions)
                for child in document.children {
                    if let block = parseBlockElement(child, index: &index) {
                        if case .footnoteDefinition(let id, _) = block.type {
                            footnotes[id] = block
                        } else {
                            blocks.append(block)
                        }
                    }
                }
            }
        }

        return ParsedMarkdownDocument(
            blocks: blocks,
            footnotes: footnotes,
            isComplete: true,
            streamingBuffer: ""
        )
    }

    /// Extract $$...$$ block math from content, skipping fenced code blocks
    private func extractMathBlocks(from content: String) -> [(content: String, isMath: Bool)] {
        var segments: [(content: String, isMath: Bool)] = []
        var current = ""
        var inCodeFence = false

        func flushCurrentIfNeeded() {
            if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append((current, false))
            }
            current = ""
        }

        func isFenceStart(at index: String.Index) -> Bool {
            guard content[index...].hasPrefix("```") else { return false }
            let lineStart = content[..<index].lastIndex(of: "\n").map { content.index(after: $0) } ?? content.startIndex
            let prefix = content[lineStart..<index]
            return prefix.allSatisfy { $0 == " " || $0 == "\t" }
        }

        var i = content.startIndex
        while i < content.endIndex {
            if isFenceStart(at: i) {
                inCodeFence.toggle()
                current.append(contentsOf: "```")
                i = content.index(i, offsetBy: 3)
                continue
            }

            if !inCodeFence && content[i...].hasPrefix("$$") {
                flushCurrentIfNeeded()

                let afterStart = content.index(i, offsetBy: 2)
                if let endRange = content[afterStart...].range(of: "$$") {
                    let mathContent = String(content[afterStart..<endRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !mathContent.isEmpty {
                        segments.append((mathContent, true))
                    }
                    i = endRange.upperBound
                    continue
                } else {
                    // Unclosed $$, treat rest as non-math
                    current.append(contentsOf: content[i...])
                    break
                }
            }

            current.append(content[i])
            i = content.index(after: i)
        }

        flushCurrentIfNeeded()

        return segments.isEmpty ? [(content, false)] : segments
    }

    /// Parse markdown content with streaming support
    func parseStreaming(_ content: String, isComplete: Bool) -> ParsedMarkdownDocument {
        if isComplete {
            return parse(content)
        }

        let (stableContent, buffer) = findStableBoundary(in: content)

        if stableContent.isEmpty {
            return ParsedMarkdownDocument(
                blocks: [],
                footnotes: [:],
                isComplete: false,
                streamingBuffer: content
            )
        }

        let result = parse(stableContent)
        return ParsedMarkdownDocument(
            blocks: result.blocks,
            footnotes: result.footnotes,
            isComplete: false,
            streamingBuffer: buffer
        )
    }

    // MARK: - Block Parsing

    private func parseBlockElement(_ element: Markup, index: inout Int) -> MarkdownBlock? {
        defer { index += 1 }

        switch element {
        case let paragraph as Paragraph:
            return parseParagraph(paragraph, index: index)

        case let heading as Heading:
            let content = parseInlineContent(heading.children)
            return MarkdownBlock(.heading(content, level: heading.level), index: index)

        case let codeBlock as CodeBlock:
            return parseCodeBlock(codeBlock, index: index)

        case let list as UnorderedList:
            return parseList(list, ordered: false, startIndex: 1, index: index)

        case let list as OrderedList:
            return parseList(list, ordered: true, startIndex: Int(list.startIndex), index: index)

        case let quote as BlockQuote:
            return parseBlockQuote(quote, index: index)

        case let table as Markdown.Table:
            return parseTable(table, index: index)

        case is ThematicBreak:
            return MarkdownBlock(.thematicBreak, index: index)

        case let html as HTMLBlock:
            return MarkdownBlock(.htmlBlock(html.rawHTML), index: index)

        default:
            return nil
        }
    }

    private func parseParagraph(_ paragraph: Paragraph, index: Int) -> MarkdownBlock? {
        // Check if paragraph contains only an image
        if paragraph.childCount == 1,
           let image = paragraph.children.first(where: { _ in true }) as? Markdown.Image {
            return MarkdownBlock(.image(url: image.source ?? "", alt: extractAltText(from: image)), index: index)
        }

        let content = parseInlineContent(paragraph.children)
        guard !content.isEmpty else { return nil }

        // Check if paragraph is a footnote definition [^id]: content
        if let (footnoteId, footnoteContent) = extractFootnoteDefinition(from: content) {
            let defContent = MarkdownInlineContent(elements: [.text(footnoteContent)])
            let defBlock = MarkdownBlock(.paragraph(defContent), index: 0)
            return MarkdownBlock(.footnoteDefinition(id: footnoteId, blocks: [defBlock]), index: index)
        }

        // Check if paragraph is a standalone LaTeX equation
        if let mathContent = extractStandaloneMath(from: content) {
            return MarkdownBlock(.mathBlock(mathContent), index: index)
        }

        return MarkdownBlock(.paragraph(content), index: index)
    }

    /// Extract footnote definition [^id]: content from inline content
    private func extractFootnoteDefinition(from content: MarkdownInlineContent) -> (id: String, content: String)? {
        let plainText = content.plainText
        // Check for pattern: [^id]: content
        guard plainText.hasPrefix("[^") else { return nil }

        // Find the closing bracket and colon
        guard let closeBracket = plainText.firstIndex(of: "]") else { return nil }
        let afterBracket = plainText.index(after: closeBracket)
        guard afterBracket < plainText.endIndex, plainText[afterBracket] == ":" else { return nil }

        // Extract ID (between [^ and ])
        let idStart = plainText.index(plainText.startIndex, offsetBy: 2)
        let id = String(plainText[idStart..<closeBracket])
        guard !id.isEmpty else { return nil }

        // Extract content (after ": ")
        var contentStart = plainText.index(after: afterBracket)
        if contentStart < plainText.endIndex && plainText[contentStart] == " " {
            contentStart = plainText.index(after: contentStart)
        }
        let footnoteContent = String(plainText[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return (id, footnoteContent)
    }

    /// Detect if inline content is actually a standalone math equation
    private func extractStandaloneMath(from content: MarkdownInlineContent) -> String? {
        let plainText = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for $...$ wrapped content (single line)
        if plainText.hasPrefix("$") && plainText.hasSuffix("$") && !plainText.hasPrefix("$$") {
            let inner = String(plainText.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty && looksLikeLaTeX(inner) {
                return inner
            }
        }

        // Check for raw LaTeX patterns (equations without $ delimiters)
        if looksLikeLaTeXBlock(plainText) {
            return plainText
        }

        return nil
    }

    /// Check if text looks like LaTeX math content
    private func looksLikeLaTeX(_ text: String) -> Bool {
        let mathPatterns = ["\\frac", "\\sqrt", "\\sum", "\\int", "\\prod", "\\lim",
                           "\\begin{", "\\end{", "^{", "_{", "\\alpha", "\\beta",
                           "\\gamma", "\\delta", "\\theta", "\\pi", "\\infty",
                           "\\partial", "\\nabla", "\\times", "\\cdot", "\\pm"]
        return mathPatterns.contains { text.contains($0) }
    }

    /// Check if entire text looks like a LaTeX block equation
    private func looksLikeLaTeXBlock(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with backslash (LaTeX command)
        guard trimmed.hasPrefix("\\") else { return false }

        // Check for common block math patterns
        let blockPatterns = ["\\frac{", "\\sqrt{", "\\sum_", "\\sum^", "\\int_", "\\int^",
                            "\\prod_", "\\lim_", "\\begin{", "\\left", "\\right",
                            "\\mathbf{", "\\mathrm{", "\\text{"]
        return blockPatterns.contains { trimmed.hasPrefix($0) || trimmed.contains($0) }
    }

    private func parseCodeBlock(_ codeBlock: CodeBlock, index: Int) -> MarkdownBlock {
        let language = codeBlock.language?.lowercased()

        if language == "mermaid" {
            return MarkdownBlock(.mermaidDiagram(codeBlock.code), index: index)
        }

        if language == "math" || language == "latex" || language == "tex" {
            return MarkdownBlock(.mathBlock(codeBlock.code), index: index)
        }

        return MarkdownBlock(.codeBlock(code: codeBlock.code, language: codeBlock.language, isStreaming: false), index: index)
    }

    private func parseList(_ list: ListItemContainer, ordered: Bool, startIndex: Int, index: Int) -> MarkdownBlock {
        var items: [MarkdownListItem] = []
        var itemIndex = 0

        for item in list.listItems {
            let parsedItem = parseListItem(
                item,
                depth: 0,
                index: itemIndex,
                listOrdered: ordered,
                listStartIndex: startIndex
            )
            items.append(parsedItem)
            itemIndex += 1
        }

        return MarkdownBlock(.list(items: items, ordered: ordered, startIndex: startIndex), index: index)
    }

    private func parseListItem(
        _ item: Markdown.ListItem,
        depth: Int,
        index: Int,
        listOrdered: Bool,
        listStartIndex: Int
    ) -> MarkdownListItem {
        var checkbox: MarkdownListItem.CheckboxState? = nil

        // Check for checkbox in the item's checkbox property
        if let cb = item.checkbox {
            checkbox = cb == .checked ? .checked : .unchecked
        }

        var inlineChildren: [Markup] = []
        var nestedLists: [(ListItemContainer, Bool, Int)] = []

        for child in item.children {
            if let list = child as? UnorderedList {
                nestedLists.append((list, false, 1))
            } else if let list = child as? OrderedList {
                nestedLists.append((list, true, Int(list.startIndex)))
            } else if let paragraph = child as? Paragraph {
                for c in paragraph.children { inlineChildren.append(c) }
            } else {
                inlineChildren.append(child)
            }
        }

        var content = parseInlineContent(inlineChildren)

        // Handle manual checkbox syntax if checkbox property wasn't set
        if checkbox == nil, case .text(var text) = content.elements.first {
            if text.hasPrefix("[ ] ") {
                checkbox = .unchecked
                text = String(text.dropFirst(4))
                var newElements = content.elements
                newElements[0] = .text(text)
                content = MarkdownInlineContent(elements: newElements)
            } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                checkbox = .checked
                text = String(text.dropFirst(4))
                var newElements = content.elements
                newElements[0] = .text(text)
                content = MarkdownInlineContent(elements: newElements)
            }
        }

        var children: [MarkdownListItem] = []
        for (nestedList, nestedOrdered, nestedStartIndex) in nestedLists {
            var nestedIndex = 0
            for nestedItem in nestedList.listItems {
                children.append(
                    parseListItem(
                        nestedItem,
                        depth: depth + 1,
                        index: nestedIndex,
                        listOrdered: nestedOrdered,
                        listStartIndex: nestedStartIndex
                    )
                )
                nestedIndex += 1
            }
        }

        return MarkdownListItem(
            content: content,
            children: children,
            checkbox: checkbox,
            depth: depth,
            index: index,
            listOrdered: listOrdered,
            listStartIndex: listStartIndex
        )
    }

    private func parseBlockQuote(_ quote: BlockQuote, index: Int) -> MarkdownBlock {
        var blocks: [MarkdownBlock] = []
        var blockIndex = 0

        for child in quote.children {
            if let block = parseBlockElement(child, index: &blockIndex) {
                blocks.append(block)
            }
        }

        return MarkdownBlock(.blockQuote(blocks: blocks), index: index)
    }

    private func parseTable(_ table: Markdown.Table, index: Int) -> MarkdownBlock {
        var rows: [MarkdownTableRow] = []

        let headerCells = table.head.cells.map { self.parseInlineContent($0.children) }
        rows.append(MarkdownTableRow(cells: Array(headerCells), isHeader: true, index: 0))

        var rowIndex = 1
        for row in table.body.rows {
            let cells = row.cells.map { self.parseInlineContent($0.children) }
            rows.append(MarkdownTableRow(cells: Array(cells), isHeader: false, index: rowIndex))
            rowIndex += 1
        }

        let alignments = table.columnAlignments.map { ColumnAlignment(from: $0) }

        return MarkdownBlock(.table(rows: rows, alignments: Array(alignments)), index: index)
    }

    // MARK: - Inline Parsing

    private func parseInlineContent<S: Sequence>(_ elements: S) -> MarkdownInlineContent where S.Element == Markup {
        var result: [InlineElement] = []

        for element in elements {
            result.append(contentsOf: parseInlineElement(element))
        }

        return MarkdownInlineContent(elements: result)
    }

    private func parseInlineElement(_ element: Markup) -> [InlineElement] {
        switch element {
        case let text as Markdown.Text:
            return parseTextWithMath(text.string)

        case let emphasis as Emphasis:
            let content = parseInlineContent(emphasis.children)
            return [.emphasis(content)]

        case let strong as Strong:
            let content = parseInlineContent(strong.children)
            return [.strong(content)]

        case let strikethrough as Strikethrough:
            let content = parseInlineContent(strikethrough.children)
            return [.strikethrough(content)]

        case let code as InlineCode:
            return [.code(code.code)]

        case let link as Markdown.Link:
            let content = parseInlineContent(link.children)
            return [.link(text: content, url: link.destination ?? "", title: link.title)]

        case let image as Markdown.Image:
            return [.image(url: image.source ?? "", alt: extractAltText(from: image), title: image.title)]

        case is SoftBreak:
            return [.softBreak]

        case is LineBreak:
            return [.hardBreak]

        case let html as InlineHTML:
            return [.html(html.rawHTML)]

        default:
            return []
        }
    }

    private func parseTextWithMath(_ text: String) -> [InlineElement] {
        var result: [InlineElement] = []
        var currentText = ""
        var i = text.startIndex

        while i < text.endIndex {
            // Check for footnote reference [^id]
            if text[i] == "[" {
                if let (footnoteId, endIndex) = extractFootnoteReference(text, from: i) {
                    if !currentText.isEmpty {
                        result.append(.text(currentText))
                        currentText = ""
                    }
                    result.append(.footnoteReference(id: footnoteId))
                    i = endIndex
                    continue
                }
            }

            // Check for inline math $...$
            if text[i] == "$" {
                let next = text.index(after: i)
                // Skip $$ (block math)
                if next < text.endIndex && text[next] == "$" {
                    currentText.append(text[i])
                    i = next
                    currentText.append(text[i])
                    i = text.index(after: i)
                    continue
                }

                // Try to extract inline math
                if let (math, endIndex) = extractInlineMath(text, from: i) {
                    if !currentText.isEmpty {
                        result.append(.text(currentText))
                        currentText = ""
                    }
                    result.append(.math(math))
                    i = endIndex
                    continue
                }
            }

            currentText.append(text[i])
            i = text.index(after: i)
        }

        if !currentText.isEmpty {
            result.append(.text(currentText))
        }

        return result.isEmpty ? [.text(text)] : result
    }

    /// Extract footnote reference [^id] from text
    private func extractFootnoteReference(_ text: String, from start: String.Index) -> (String, String.Index)? {
        guard text[start] == "[" else { return nil }
        let afterBracket = text.index(after: start)
        guard afterBracket < text.endIndex, text[afterBracket] == "^" else { return nil }

        // Find the closing ]
        var current = text.index(after: afterBracket)
        var id = ""

        while current < text.endIndex {
            if text[current] == "]" {
                if !id.isEmpty {
                    return (id, text.index(after: current))
                }
                return nil
            }
            // Footnote IDs can contain alphanumeric, hyphen, underscore
            let char = text[current]
            if char.isLetter || char.isNumber || char == "-" || char == "_" {
                id.append(char)
            } else {
                return nil // Invalid character in footnote ID
            }
            current = text.index(after: current)
        }
        return nil
    }

    private func extractInlineMath(_ text: String, from start: String.Index) -> (String, String.Index)? {
        guard text[start] == "$" else { return nil }
        let afterDollar = text.index(after: start)
        guard afterDollar < text.endIndex else { return nil }

        // Don't match if starts with space
        if text[afterDollar] == " " { return nil }

        var current = afterDollar
        while current < text.endIndex {
            if text[current] == "$" {
                // Don't match if ends with space
                let beforeDollar = text.index(before: current)
                if beforeDollar >= afterDollar && text[beforeDollar] == " " { return nil }

                let content = String(text[afterDollar..<current])
                if !content.isEmpty {
                    return (content, text.index(after: current))
                }
                return nil
            }
            if text[current] == "\n" { return nil }
            current = text.index(after: current)
        }
        return nil
    }

    private func extractAltText(from image: Markdown.Image) -> String? {
        var alt = ""
        for child in image.children {
            if let text = child as? Markdown.Text {
                alt += text.string
            }
        }
        return alt.isEmpty ? nil : alt
    }

    private func findStableBoundary(in content: String) -> (stable: String, buffer: String) {
        var inCodeBlock = false
        var inMathBlock = false
        var codeBlockStart: String.Index?
        var mathBlockStart: String.Index?
        var lastStableBoundary = content.startIndex
        var i = content.startIndex

        while i < content.endIndex {
            // Check for $$ math block
            if content[i] == "$" && !inCodeBlock {
                let remaining = content[i...]
                if remaining.hasPrefix("$$") {
                    if inMathBlock {
                        // End of math block
                        let endOfMath = content.index(i, offsetBy: 2, limitedBy: content.endIndex) ?? content.endIndex
                        inMathBlock = false
                        mathBlockStart = nil
                        lastStableBoundary = endOfMath
                        i = endOfMath
                        continue
                    } else {
                        // Start of math block
                        inMathBlock = true
                        mathBlockStart = i
                        i = content.index(i, offsetBy: 2, limitedBy: content.endIndex) ?? content.endIndex
                        continue
                    }
                }
            }

            // Check for ``` code block
            if content[i] == "`" && !inMathBlock {
                let remaining = content[i...]
                if remaining.hasPrefix("```") {
                    if inCodeBlock {
                        var endOfLine = content.index(i, offsetBy: 3, limitedBy: content.endIndex) ?? content.endIndex
                        while endOfLine < content.endIndex && content[endOfLine] != "\n" {
                            endOfLine = content.index(after: endOfLine)
                        }
                        if endOfLine < content.endIndex {
                            endOfLine = content.index(after: endOfLine)
                        }
                        inCodeBlock = false
                        codeBlockStart = nil
                        lastStableBoundary = endOfLine
                        i = endOfLine
                        continue
                    } else {
                        inCodeBlock = true
                        codeBlockStart = i
                    }
                }
            }

            if !inCodeBlock && !inMathBlock && content[i] == "\n" {
                let next = content.index(after: i)
                if next < content.endIndex && content[next] == "\n" {
                    lastStableBoundary = content.index(after: next)
                }
            }

            i = content.index(after: i)
        }

        // If we're inside an unclosed block, reset to before that block
        if inCodeBlock, let start = codeBlockStart {
            lastStableBoundary = start
        }
        if inMathBlock, let start = mathBlockStart {
            lastStableBoundary = min(lastStableBoundary, start)
        }

        let stable = String(content[..<lastStableBoundary])
        let buffer = String(content[lastStableBoundary...])

        return (stable, buffer)
    }
}

// MARK: - AttributedString Rendering

extension MarkdownInlineContent {

    func attributedString(
        baseFont: Font = .body,
        baseColor: Color = .primary
    ) -> AttributedString {
        var result = AttributedString()

        for element in elements {
            result += element.attributedString(baseFont: baseFont, baseColor: baseColor)
        }

        return result
    }

    func nsAttributedString(
        baseFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
        baseColor: NSColor = .labelColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for element in elements {
            result.append(element.nsAttributedString(baseFont: baseFont, baseColor: baseColor))
        }

        return result
    }
}

extension InlineElement {

    func attributedString(baseFont: Font, baseColor: Color) -> AttributedString {
        switch self {
        case .text(let text):
            var attr = AttributedString(text)
            attr.font = baseFont
            attr.foregroundColor = baseColor
            return attr

        case .emphasis(let content):
            var attr = content.attributedString(baseFont: baseFont, baseColor: baseColor)
            attr.font = baseFont.italic()
            return attr

        case .strong(let content):
            var attr = content.attributedString(baseFont: baseFont, baseColor: baseColor)
            attr.font = baseFont.bold()
            return attr

        case .strikethrough(let content):
            var attr = content.attributedString(baseFont: baseFont, baseColor: baseColor)
            attr.strikethroughStyle = .single
            return attr

        case .code(let code):
            var attr = AttributedString(code)
            attr.font = .system(.body, design: .monospaced)
            attr.backgroundColor = Color(nsColor: .quaternaryLabelColor)
            return attr

        case .link(let text, let url, _):
            var attr = text.attributedString(baseFont: baseFont, baseColor: .blue)
            attr.underlineStyle = .single
            if let linkURL = URL(string: url) {
                attr.link = linkURL
            }
            return attr

        case .image(_, let alt, _):
            var attr = AttributedString(alt ?? "[image]")
            attr.foregroundColor = .secondary
            return attr

        case .softBreak:
            return AttributedString(" ")

        case .hardBreak:
            return AttributedString("\n")

        case .html(let html):
            var attr = AttributedString(html)
            attr.font = .system(.body, design: .monospaced)
            attr.foregroundColor = .secondary
            return attr

        case .math(let math):
            var attr = AttributedString("$\(math)$")
            attr.font = .system(.body, design: .monospaced)
            attr.foregroundColor = Color(nsColor: .systemPurple)
            return attr

        case .footnoteReference(let id):
            var attr = AttributedString("[\(id)]")
            attr.font = .caption
            attr.foregroundColor = .blue
            attr.baselineOffset = 4
            return attr
        }
    }

    func nsAttributedString(baseFont: NSFont, baseColor: NSColor) -> NSAttributedString {
        switch self {
        case .text(let text):
            return NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ])

        case .emphasis(let content):
            let result = NSMutableAttributedString(attributedString: content.nsAttributedString(baseFont: baseFont, baseColor: baseColor))
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            result.addAttribute(.font, value: italicFont, range: NSRange(location: 0, length: result.length))
            return result

        case .strong(let content):
            let result = NSMutableAttributedString(attributedString: content.nsAttributedString(baseFont: baseFont, baseColor: baseColor))
            let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            result.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: result.length))
            return result

        case .strikethrough(let content):
            let result = NSMutableAttributedString(attributedString: content.nsAttributedString(baseFont: baseFont, baseColor: baseColor))
            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: result.length))
            return result

        case .code(let code):
            let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            return NSAttributedString(string: code, attributes: [
                .font: monoFont,
                .foregroundColor: baseColor,
                .backgroundColor: NSColor.quaternaryLabelColor
            ])

        case .link(let text, let url, _):
            let result = NSMutableAttributedString(attributedString: text.nsAttributedString(baseFont: baseFont, baseColor: .linkColor))
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: result.length))
            if let linkURL = URL(string: url) {
                result.addAttribute(.link, value: linkURL, range: NSRange(location: 0, length: result.length))
            }
            return result

        case .image(_, let alt, _):
            return NSAttributedString(string: alt ?? "[image]", attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])

        case .softBreak:
            return NSAttributedString(string: " ")

        case .hardBreak:
            return NSAttributedString(string: "\n")

        case .html(let html):
            let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            return NSAttributedString(string: html, attributes: [
                .font: monoFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])

        case .math(let math):
            let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            return NSAttributedString(string: "$\(math)$", attributes: [
                .font: monoFont,
                .foregroundColor: NSColor.systemPurple
            ])

        case .footnoteReference(let id):
            let smallFont = NSFont.systemFont(ofSize: baseFont.pointSize - 2)
            return NSAttributedString(string: "[\(id)]", attributes: [
                .font: smallFont,
                .foregroundColor: NSColor.linkColor,
                .baselineOffset: 4
            ])
        }
    }
}
