//
//  LanguageDetection.swift
//  aizen
//
//  Helper utilities for detecting programming languages from MIME types and file extensions
//

import Foundation
import HighlightSwift

struct LanguageDetection {
    /// Convert markdown code fence language identifier to HighlightLanguage
    static func highlightLanguageFromFence(_ fenceLang: String) -> HighlightLanguage? {
        let normalized = normalizeLanguageIdentifier(fenceLang)
        return HighlightLanguage(rawValue: normalized)
    }

    /// Detect programming language from MIME type and URI, returns HighlightLanguage
    static func detectHighlightLanguage(mimeType: String?, uri: String) -> HighlightLanguage? {
        if let langString = detectLanguage(mimeType: mimeType, uri: uri) {
            return HighlightLanguage(rawValue: langString)
        }
        return nil
    }

    /// Normalize language identifiers to match HighlightLanguage enum cases
    private static func normalizeLanguageIdentifier(_ lang: String) -> String {
        let lower = lang.lowercased()

        let aliases: [String: String] = [
            "jsx": "javascript",
            "tsx": "typescript",
            "sh": "bash",
            "zsh": "bash",
            "c++": "cpp",
            "c#": "csharp",
            "objective-c": "objectivec",
            "objc": "objectivec",
            "py": "python",
            "js": "javascript",
            "ts": "typescript",
            "rb": "ruby",
            "yml": "yaml",
        ]

        return aliases[lower] ?? lower
    }

    /// Detect programming language from MIME type and URI, returns string identifier
    static func detectLanguage(mimeType: String?, uri: String) -> String? {
        // Try MIME type first
        if let mimeType = mimeType?.lowercased() {
            if let lang = languageFromMimeType(mimeType) {
                return lang
            }
        }

        // Fall back to file extension
        if let url = URL(string: uri) {
            let ext = url.pathExtension.lowercased()
            return languageFromExtension(ext)
        }

        return nil
    }

    /// Map MIME types to highlight.js language identifiers
    private static let mimeTypeMapping: [String: String] = [
            // Swift
            "text/x-swift": "swift",
            "application/x-swift": "swift",

            // JavaScript/TypeScript
            "text/javascript": "javascript",
            "application/javascript": "javascript",
            "application/x-javascript": "javascript",
            "text/typescript": "typescript",
            "application/typescript": "typescript",

            // Python
            "text/x-python": "python",
            "application/x-python": "python",

            // Ruby
            "text/x-ruby": "ruby",
            "application/x-ruby": "ruby",

            // Java
            "text/x-java": "java",
            "text/x-java-source": "java",

            // C/C++
            "text/x-c": "c",
            "text/x-c++": "cpp",
            "text/x-c++src": "cpp",

            // Go
            "text/x-go": "go",

            // Rust
            "text/x-rust": "rust",

            // HTML/CSS
            "text/html": "html",
            "text/css": "css",

            // JSON/XML
            "application/json": "json",
            "text/json": "json",
            "application/xml": "xml",
            "text/xml": "xml",

            // Markdown
            "text/markdown": "markdown",
            "text/x-markdown": "markdown",

            // Shell
            "text/x-sh": "bash",
            "text/x-shellscript": "bash",
            "application/x-sh": "bash",

            // SQL
            "text/x-sql": "sql",
            "application/sql": "sql",

            // YAML
            "text/yaml": "yaml",
            "text/x-yaml": "yaml",
            "application/x-yaml": "yaml",
        ]

    private static func languageFromMimeType(_ mimeType: String) -> String? {
        return mimeTypeMapping[mimeType]
    }

    /// Map file extensions to highlight.js language identifiers
    private static let extensionMapping: [String: String] = [
            // Swift
            "swift": "swift",

            // JavaScript/TypeScript
            "js": "javascript",
            "jsx": "javascript",
            "mjs": "javascript",
            "cjs": "javascript",
            "ts": "typescript",
            "tsx": "typescript",

            // Python
            "py": "python",
            "pyw": "python",
            "pyi": "python",

            // Ruby
            "rb": "ruby",
            "erb": "ruby",

            // Java
            "java": "java",

            // Kotlin
            "kt": "kotlin",
            "kts": "kotlin",

            // C/C++
            "c": "c",
            "h": "c",
            "cpp": "cpp",
            "cc": "cpp",
            "cxx": "cpp",
            "hpp": "cpp",
            "hh": "cpp",

            // C#
            "cs": "csharp",

            // Go
            "go": "go",

            // Rust
            "rs": "rust",

            // PHP
            "php": "php",

            // HTML/CSS
            "html": "html",
            "htm": "html",
            "css": "css",
            "scss": "scss",
            "sass": "sass",
            "less": "less",

            // JSON/XML
            "json": "json",
            "xml": "xml",

            // Markdown
            "md": "markdown",
            "markdown": "markdown",

            // Shell
            "sh": "bash",
            "bash": "bash",
            "zsh": "bash",

            // SQL
            "sql": "sql",

            // YAML
            "yaml": "yaml",
            "yml": "yaml",

            // Docker
            "dockerfile": "dockerfile",

            // Makefile
            "makefile": "makefile",
            "make": "makefile",

            // Lua
            "lua": "lua",

            // Perl
            "pl": "perl",
            "pm": "perl",

            // R
            "r": "r",

            // Elixir
            "ex": "elixir",
            "exs": "elixir",

            // Haskell
            "hs": "haskell",

            // Scala
            "scala": "scala",

            // Clojure
            "clj": "clojure",
            "cljs": "clojure",

            // Vue
            "vue": "vue",

            // GraphQL
            "graphql": "graphql",
            "gql": "graphql",
        ]

    private static func languageFromExtension(_ ext: String) -> String? {
        return extensionMapping[ext]
    }

    /// Check if a file is likely to contain code based on MIME type or extension
    static func isCodeFile(mimeType: String?, uri: String) -> Bool {
        return detectLanguage(mimeType: mimeType, uri: uri) != nil
    }
}
