//
//  FileSearchService.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation

struct FileSearchIndexResult: Identifiable, Sendable {
    let path: String
    let relativePath: String
    let isDirectory: Bool
    var matchScore: Double = 0

    var id: String { path }
}

actor FileSearchService {
    static let shared = FileSearchService()

    private var cachedResults: [String: [FileSearchIndexResult]] = [:]
    private var recentFiles: [String: [String]] = [:]
    private let maxRecentFiles = 10
    private var gitignorePatterns: [String] = []

    private init() {}

    // Index files in directory recursively with gitignore support
    func indexDirectory(_ path: String) async throws -> [FileSearchIndexResult] {
        // Check cache first
        if let cached = cachedResults[path] {
            return cached
        }

        // Load gitignore patterns and index manually
        await loadGitignorePatterns(at: path)
        let results = await indexDirectoryManually(path)

        // Cache results
        cachedResults[path] = results
        return results
    }

    // Directory indexing with gitignore patterns
    private func indexDirectoryManually(_ path: String) async -> [FileSearchIndexResult] {
        var results: [FileSearchIndexResult] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let basePath = path

        while let fileURL = enumerator.nextObject() as? URL {
            // Skip hidden files and directories
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isHiddenKey]),
               resourceValues.isHidden == true {
                continue
            }

            let isDirectory = fileURL.hasDirectoryPath

            // Skip directories - only index files
            if isDirectory {
                let dirName = fileURL.lastPathComponent
                let dirRelativePath = fileURL.path.replacingOccurrences(of: basePath + "/", with: "")
                if matchesGitignore(dirRelativePath) || matchesGitignore(dirName) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let fileName = fileURL.lastPathComponent
            let fullPath = fileURL.path
            let relativePath = fullPath.replacingOccurrences(of: basePath + "/", with: "")

            // Skip if matches gitignore patterns
            if matchesGitignore(relativePath) || matchesGitignore(fileName) {
                continue
            }

            let result = FileSearchIndexResult(
                path: fullPath,
                relativePath: relativePath,
                isDirectory: false
            )
            results.append(result)
        }

        return results
    }

    // Load gitignore patterns from .gitignore file
    private func loadGitignorePatterns(at path: String) async {
        // Start with common patterns that should always be ignored
        gitignorePatterns = [
            ".git",
            "node_modules",
            ".build",
            "DerivedData",
            ".swiftpm",
            "Pods",
            "Carthage",
            ".DS_Store",
            "*.xcodeproj",
            "*.xcworkspace",
            "xcuserdata",
            "__pycache__",
            ".venv",
            "venv",
            ".env",
            "dist",
            "build",
            ".next",
            ".nuxt",
            "target",
            "vendor"
        ]

        let gitignorePath = (path as NSString).appendingPathComponent(".gitignore")

        if let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) {
            let filePatterns = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("!") }

            gitignorePatterns.append(contentsOf: filePatterns)
        }
    }

    // Check if path matches gitignore patterns - simplified matching
    private func matchesGitignore(_ path: String) -> Bool {
        let pathComponents = path.components(separatedBy: "/")

        for pattern in gitignorePatterns {
            var cleanPattern = pattern
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // Handle glob patterns like *.log
            if cleanPattern.hasPrefix("*") {
                let suffix = String(cleanPattern.dropFirst())
                if path.hasSuffix(suffix) || pathComponents.last?.hasSuffix(suffix) == true {
                    return true
                }
                continue
            }

            // Check if any path component matches the pattern exactly
            if pathComponents.contains(cleanPattern) {
                return true
            }

            // Check if path starts with pattern (for directory patterns)
            if path.hasPrefix(cleanPattern + "/") || path == cleanPattern {
                return true
            }
        }

        return false
    }

    // Fuzzy search with scoring
    func search(query: String, in results: [FileSearchIndexResult], worktreePath: String) async -> [FileSearchIndexResult] {
        guard !query.isEmpty else {
            // Return recent files when query is empty, or all results if no recent files
            let recent = getRecentFileResults(for: worktreePath, from: results)
            return recent.isEmpty ? results : recent
        }

        let lowercaseQuery = query.lowercased()
        var scoredResults: [FileSearchIndexResult] = []

        for var result in results {
            let fileName = result.path
                .split(separator: "/")
                .last
                .map { String($0).lowercased() } ?? ""
            let relativePath = result.relativePath.lowercased()

            // Score filename match (higher weight)
            let fileNameScore = fuzzyMatch(query: lowercaseQuery, target: fileName)

            // Score relative path match (lower weight)
            let pathScore = fuzzyMatch(query: lowercaseQuery, target: relativePath) * 0.6

            let totalScore = max(fileNameScore, pathScore)
            if totalScore > 0 {
                result.matchScore = totalScore
                scoredResults.append(result)
            }
        }

        // Sort by score (higher is better)
        return scoredResults.sorted { $0.matchScore > $1.matchScore }
    }

    // Track recently opened files
    func addRecentFile(_ path: String, worktreePath: String) {
        var files = recentFiles[worktreePath] ?? []
        files.removeAll { $0 == path }
        files.insert(path, at: 0)
        if files.count > maxRecentFiles {
            files.removeLast()
        }
        recentFiles[worktreePath] = files
    }

    // Get recent files as results
    private func getRecentFileResults(for worktreePath: String, from allResults: [FileSearchIndexResult]) -> [FileSearchIndexResult] {
        guard let files = recentFiles[worktreePath] else { return [] }

        var results: [FileSearchIndexResult] = []
        for recentPath in files {
            if let result = allResults.first(where: { $0.path == recentPath }) {
                results.append(result)
            }
        }
        return results
    }

    // Clear cache for specific path
    func clearCache(for path: String) {
        cachedResults.removeValue(forKey: path)
        recentFiles.removeValue(forKey: path)
    }

    // Clear all caches
    func clearAllCaches() {
        cachedResults.removeAll()
        recentFiles.removeAll()
    }

    // MARK: - Private Helpers

    // Fuzzy matching algorithm with scoring
    private func fuzzyMatch(query: String, target: String) -> Double {
        guard !query.isEmpty else { return 0 }

        var score: Double = 0
        var queryIndex = query.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveMatches = 0

        // Bonus for exact match
        if target == query {
            return 1000.0
        }

        // Bonus for prefix match
        if target.hasPrefix(query) {
            return 500.0 + Double(query.count)
        }

        // Fuzzy matching
        for (targetIndex, targetChar) in target.enumerated() {
            if queryIndex < query.endIndex && targetChar == query[queryIndex] {
                // Base score for match
                score += 10.0

                // Bonus for consecutive matches
                if let last = lastMatchIndex, target.index(after: last) == target.index(target.startIndex, offsetBy: targetIndex) {
                    consecutiveMatches += 1
                    score += Double(consecutiveMatches) * 5.0
                } else {
                    consecutiveMatches = 0
                }

                // Bonus for matching start of word
                if targetIndex == 0 || target[target.index(target.startIndex, offsetBy: targetIndex - 1)] == "/" || target[target.index(target.startIndex, offsetBy: targetIndex - 1)] == "." {
                    score += 15.0
                }

                // Bonus for uppercase match (camelCase)
                if targetChar.isUppercase {
                    score += 10.0
                }

                lastMatchIndex = target.index(target.startIndex, offsetBy: targetIndex)
                queryIndex = query.index(after: queryIndex)
            }
        }

        // Check if all query characters were matched
        if queryIndex == query.endIndex {
            // Penalty for longer paths (prefer shorter paths)
            score -= Double(target.count) * 0.1
            return score
        }

        return 0
    }
}
