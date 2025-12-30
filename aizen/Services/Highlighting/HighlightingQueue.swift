//
//  HighlightingQueue.swift
//  aizen
//
//  Queued syntax highlighting with concurrency limits and caching
//

import Foundation
import SwiftUI
import CodeEditLanguages
import CodeEditSourceEditor

/// Manages syntax highlighting with concurrency limits to prevent CPU overload
actor HighlightingQueue {
    static let shared = HighlightingQueue()

    // Cache for highlighted results (keyed by content hash + language)
    private var cache: [Int: AttributedString] = [:]
    private let maxCacheSize = 100
    private let maxHighlightCharacters = 4000
    private let maxHighlightLines = 200

    // Concurrency control
    private var activeCount = 0
    private let maxConcurrent = 2

    // Internal highlighter
    private let highlighter = TreeSitterHighlighter()

    private init() {}

    /// Highlight code with queuing and caching
    func highlight(
        code: String,
        language: CodeLanguage,
        theme: EditorTheme
    ) async -> AttributedString? {
        if code.count > maxHighlightCharacters {
            return nil
        }

        var lineCount = 1
        for char in code where char == "\n" {
            lineCount += 1
            if lineCount > maxHighlightLines {
                return nil
            }
        }

        // Generate cache key from content and language
        let cacheKey = code.hashValue ^ language.id.hashValue

        // Check cache first
        if let cached = cache[cacheKey] {
            return cached
        }

        // Wait if at concurrency limit
        while activeCount >= maxConcurrent {
            await Task.yield()
            // Check for cancellation while waiting
            if Task.isCancelled { return nil }
        }

        // Check cancellation before starting work
        guard !Task.isCancelled else { return nil }

        activeCount += 1
        defer { activeCount -= 1 }

        do {
            let result = try await highlighter.highlightCode(code, language: language, theme: theme)

            // Store in cache
            if cache.count >= maxCacheSize {
                // Remove oldest entry (simple LRU approximation)
                if let firstKey = cache.keys.first {
                    cache.removeValue(forKey: firstKey)
                }
            }
            cache[cacheKey] = result

            return result
        } catch {
            return nil
        }
    }

    /// Clear the cache (e.g., when theme changes)
    func clearCache() {
        cache.removeAll()
    }
}
