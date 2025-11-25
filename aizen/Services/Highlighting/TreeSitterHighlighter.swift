//
//  TreeSitterHighlighter.swift
//  aizen
//
//  Tree-sitter based syntax highlighting service
//

import Foundation
import SwiftUI
import SwiftTreeSitter
import CodeEditLanguages
import CodeEditSourceEditor

actor TreeSitterHighlighter {
    private var parsers: [CodeLanguage: Parser] = [:]

    /// Highlight code using tree-sitter and return attributed string
    func highlightCode(
        _ text: String,
        language: CodeLanguage,
        theme: EditorTheme
    ) async throws -> AttributedString {
        // Get language for tree-sitter
        guard let tsLanguage = language.language else {
            // Language not supported, return plain text
            return AttributedString(text)
        }

        // Get or create parser for language
        let parser = try await getParser(for: language, tsLanguage: tsLanguage)

        // Parse the code
        guard let tree = parser.parse(text) else {
            // If parsing fails, return plain text
            return AttributedString(text)
        }

        // Build combined query data (parent queries first, then language-specific)
        var combinedQueryData = Data()

        // Load parent query first (if exists) for inheritance
        // TypeScript inherits from JavaScript, TSX from JSX, C++ from C, etc.
        if let parentURL = language.parentQueryURL,
           let parentData = try? Data(contentsOf: parentURL) {
            combinedQueryData.append(parentData)
            combinedQueryData.append(Data("\n".utf8))
        }

        // Load language's own query
        guard let queryURL = language.queryURL else {
            return AttributedString(text)
        }
        guard let queryData = try? Data(contentsOf: queryURL) else {
            return AttributedString(text)
        }
        combinedQueryData.append(queryData)

        // Create query from combined data
        let query = try Query(language: tsLanguage, data: combinedQueryData)

        // Execute query
        let queryCursor = query.execute(node: tree.rootNode!, in: tree)

        // Build attributed string with highlights using NSMutableAttributedString
        // for proper NSRange compatibility with tree-sitter captures
        let attributedString = NSMutableAttributedString(string: text)

        // Apply colors based on capture names
        for match in queryCursor {
            for capture in match.captures {
                guard let captureName = query.captureName(for: Int(capture.index)) else {
                    continue
                }

                if let color = HighlightThemeMapper.color(
                    for: captureName,
                    theme: theme
                ) {
                    // Use capture.range (NSRange) directly - already correctly calculated
                    let range = capture.range

                    // Validate range is within bounds
                    guard range.location != NSNotFound,
                          range.location + range.length <= (text as NSString).length else {
                        continue
                    }

                    attributedString.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }

        return AttributedString(attributedString)
    }

    /// Get or create parser for a language
    private func getParser(for language: CodeLanguage, tsLanguage: Language) async throws -> Parser {
        if let existingParser = parsers[language] {
            return existingParser
        }

        let parser = Parser()
        try parser.setLanguage(tsLanguage)
        parsers[language] = parser
        return parser
    }
}

enum HighlightError: Error {
    case unsupportedLanguage(CodeLanguage)
    case parsingFailed
}

/// Maps tree-sitter capture names to theme colors
struct HighlightThemeMapper {
    /// Map a tree-sitter capture name to a color from the theme
    /// Uses hierarchical matching to support the full tree-sitter capture group specification
    nonisolated static func color(for captureName: String, theme: EditorTheme) -> NSColor? {
        // Tree-sitter capture names follow hierarchical patterns:
        // @keyword, @keyword.function, @keyword.return, etc.
        // More specific matches should take precedence over general ones

        let name = captureName.lowercased()

        // PHASE 1: CRITICAL CAPTURES - High Visual Impact

        // HTML/JSX Tags (@tag, @tag.attribute, @tag.delimiter, @tag.builtin)
        if name.contains("tag") {
            if name.contains("attribute") {
                return theme.attributes.color // Tag attributes like href, class
            }
            if name.contains("delimiter") {
                return theme.attributes.color // <, >, </, />
            }
            return theme.types.color // Tag names like <div>, <span>
        }

        // Constructors (@constructor)
        if name.contains("constructor") {
            return theme.types.color // new MyClass(), enum constructors
        }

        // Modules and Namespaces (@module, @module.builtin, @namespace, @label)
        if name.contains("module") || name.contains("namespace") || name.contains("label") {
            return theme.types.color // import statements, package names, Rust lifetimes
        }

        // Markdown Markup (@markup.* and @text.* from CodeEditLanguages)
        if name.contains("markup") || (name.contains("text") && !name.contains("_text")) {
            // Headings (@markup.heading, @text.title)
            if name.contains("heading") || name.contains("title") {
                return theme.keywords.color // # Heading - prominent
            }
            // Links and URLs (@markup.link, @text.uri, @text.reference)
            if name.contains("link") || name.contains("url") || name.contains("uri") || name.contains("reference") {
                return theme.attributes.color // [text](url)
            }
            // Strong/Bold (@markup.strong, @text.strong)
            if name.contains("strong") || name.contains("bold") {
                return theme.keywords.color // **bold**
            }
            // Emphasis/Italic (@markup.italic, @text.emphasis)
            if name.contains("italic") || name.contains("emphasis") {
                return theme.comments.color // *italic*
            }
            // Code blocks and inline code (@markup.raw, @text.literal)
            if name.contains("raw") || name.contains("code") || name.contains("literal") {
                return theme.strings.color // `code` or ```code```
            }
            // Quotes
            if name.contains("quote") {
                return theme.comments.color // > quote
            }
            // Math
            if name.contains("math") {
                return theme.numbers.color // $math$
            }
            // Lists
            if name.contains("list") {
                return theme.attributes.color // - item, 1. item, [ ] checkbox
            }
            // Strikethrough
            if name.contains("strikethrough") {
                return theme.comments.color // ~~struck~~
            }
            // Default markup (only for "markup" or "text" prefix, not containing "_text")
            if name.starts(with: "markup") || name.starts(with: "text") {
                return theme.text.color
            }
        }

        // PHASE 2: ENHANCED DISTINCTIONS - Medium Impact

        // Built-in variables (@variable.builtin - this, self, super)
        if name.contains("variable") {
            if name.contains("builtin") {
                return theme.values.color // Highlight built-ins differently
            }
            if name.contains("property") || name.contains("parameter") || name.contains("member") {
                return theme.variables.color
            }
            return theme.variables.color
        }

        // String escape sequences (@string.escape - \n, \t, \", etc.)
        if name.contains("string") {
            if name.contains("escape") {
                return theme.attributes.color // Make escapes visible
            }
            if name.contains("character") {
                return theme.strings.color
            }
            return theme.strings.color
        }

        // Comment annotations (@comment.error, @comment.warning, @comment.todo, @comment.note)
        if name.contains("comment") {
            if name.contains("error") || name.contains("fixme") {
                return NSColor.systemRed // ERROR, FIXME - red
            }
            if name.contains("warning") || name.contains("hack") {
                return NSColor.systemOrange // WARNING, HACK - orange
            }
            if name.contains("todo") || name.contains("note") {
                return NSColor.systemBlue // TODO, NOTE - blue
            }
            return theme.comments.color
        }

        // Built-in constants (@constant.builtin - true, false, null, nil)
        if name.contains("constant") {
            if name.contains("builtin") {
                return theme.values.color
            }
            if name.contains("macro") {
                return theme.attributes.color // Preprocessor constants
            }
            return theme.values.color
        }

        // Boolean values (often separate from constants)
        if name.contains("boolean") {
            return theme.values.color
        }

        // PHASE 3: ADDITIONAL COVERAGE - Lower Priority

        // Git Diff (@diff.plus, @diff.minus, @diff.delta)
        if name.contains("diff") {
            if name.contains("plus") || name.contains("addition") {
                return NSColor.systemGreen // Added lines
            }
            if name.contains("minus") || name.contains("deletion") {
                return NSColor.systemRed // Deleted lines
            }
            if name.contains("delta") || name.contains("changed") {
                return NSColor.systemYellow // Modified lines
            }
            return theme.text.color
        }

        // Keywords (with subtypes for finer control)
        if name.contains("keyword") {
            // All keyword types get the same color, but we check subtypes
            // for potential future customization
            return theme.keywords.color
        }

        // Types and Classes
        if name.contains("type") || name.contains("class") || name.contains("interface") {
            if name.contains("builtin") {
                return theme.types.color // Built-in types like int, string
            }
            return theme.types.color
        }

        // Functions and Methods
        if name.contains("function") || name.contains("method") {
            if name.contains("builtin") {
                return theme.commands.color // Built-in functions
            }
            if name.contains("macro") {
                return theme.attributes.color // Preprocessor macros
            }
            if name.contains("call") {
                return theme.commands.color // Function calls vs definitions
            }
            return theme.commands.color
        }

        // Numbers
        if name.contains("number") || name.contains("float") || name.contains("integer") {
            return theme.numbers.color
        }

        // Operators
        if name.contains("operator") {
            return theme.attributes.color
        }

        // Attributes and decorators
        if name.contains("attribute") || name.contains("decorator") || name.contains("annotation") {
            return theme.attributes.color
        }

        // Punctuation - refined handling
        if name.contains("punctuation") {
            if name.contains("bracket") {
                return theme.attributes.color // Make brackets visible: (), {}, []
            }
            if name.contains("delimiter") {
                return theme.text.color // Delimiters more muted: ;, ., ,
            }
            if name.contains("special") {
                return theme.attributes.color // Special punctuation like ${}
            }
            return theme.text.color
        }

        // Character literals (separate from strings in some languages)
        if name.contains("character") {
            return theme.strings.color
        }

        // Default: return nil to use default text color
        return nil
    }
}
