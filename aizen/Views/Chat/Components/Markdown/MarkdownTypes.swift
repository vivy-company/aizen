//
//  MarkdownTypes.swift
//  aizen
//
//  Markdown block types for rendering
//

import SwiftUI
import Markdown

// MARK: - Markdown Block

/// Markdown block with stable ID for efficient SwiftUI diffing
struct MarkdownBlock: Identifiable {
    let id: String
    let type: MarkdownBlockType

    init(_ type: MarkdownBlockType, index: Int = 0) {
        self.type = type
        self.id = Self.generateId(for: type, index: index)
    }

    /// Generate stable ID based on content (uses hash for efficiency)
    private static func generateId(for type: MarkdownBlockType, index: Int) -> String {
        switch type {
        case .paragraph(let text):
            // Use prefix hash for paragraphs to handle streaming updates
            let contentHash = String(text.characters.prefix(100)).hashValue
            return "p-\(index)-\(contentHash)"
        case .heading(let text, let level):
            let textHash = String(text.characters).hashValue
            return "h\(level)-\(index)-\(textHash)"
        case .codeBlock(_, let lang):
            // Keep a stable ID for code blocks to avoid flicker during streaming updates.
            return "code-\(index)-\(lang ?? "none")"
        case .list(let items, let ordered):
            let itemsHash = items.count > 0 ? String(items.first!.characters.prefix(50)).hashValue : 0
            return "list-\(ordered)-\(index)-\(items.count)-\(itemsHash)"
        case .blockQuote(let text):
            let textHash = String(text.characters).hashValue
            return "quote-\(index)-\(textHash)"
        case .image(let url, _):
            return "img-\(index)-\(url.hashValue)"
        case .imageRow(let images):
            let firstHash = images.first?.url.hashValue ?? 0
            return "imgrow-\(index)-\(images.count)-\(firstHash)"
        case .mermaidDiagram(let code):
            return "mermaid-\(index)-\(code.hashValue)"
        case .table(let header, let rows, _):
            return "table-\(index)-\(header.count)x\(rows.count)"
        }
    }
}

// MARK: - Markdown Block Type

enum MarkdownBlockType {
    case paragraph(AttributedString)
    case heading(AttributedString, level: Int)
    case codeBlock(String, language: String?)
    case list([AttributedString], isOrdered: Bool)
    case blockQuote(AttributedString)
    case image(url: String, alt: String?)
    case imageRow([(url: String, alt: String?)])
    case mermaidDiagram(String)
    case table(header: [AttributedString], rows: [[AttributedString]], alignments: [Markdown.Table.ColumnAlignment?])
}
