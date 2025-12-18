//
//  FileSearchService.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation

struct FileSearchIndexResult: Identifiable, Sendable {
    let basePath: String
    let relativePath: String
    let isDirectory: Bool
    var matchScore: Double = 0

    var path: String {
        (basePath as NSString).appendingPathComponent(relativePath)
    }

    var id: String { relativePath }
}

actor FileSearchService {
    static let shared = FileSearchService()

    private var cachedResults: [String: [FileSearchIndexResult]] = [:]
    private var cacheOrder: [String] = []
    private let maxCachedDirectories = 4
    private var recentFiles: [String: [String]] = [:]
    private let maxRecentFiles = 10

    private init() {}

    // Index files in directory recursively with gitignore support
    func indexDirectory(_ path: String) async throws -> [FileSearchIndexResult] {
        // Check cache first
        if let cached = cachedResults[path] {
            touchCacheKey(path)
            return cached
        }

        let results: [FileSearchIndexResult]

        // Prefer git-aware indexing for speed + correctness (respects .gitignore).
        if FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")),
           let gitResults = await indexDirectoryWithGitLsFiles(path) {
            results = gitResults
        } else {
            results = await indexDirectoryManually(path)
        }

        // Cache results
        cachedResults[path] = results
        touchCacheKey(path)
        evictCacheIfNeeded()
        return results
    }

    // Directory indexing with gitignore patterns
    private func indexDirectoryManually(_ path: String) async -> [FileSearchIndexResult] {
        var results: [FileSearchIndexResult] = []
        let fileManager = FileManager.default
        let gitignorePatterns = loadGitignorePatterns(at: path)

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
                if matchesGitignore(dirRelativePath, patterns: gitignorePatterns) || matchesGitignore(dirName, patterns: gitignorePatterns) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let fileName = fileURL.lastPathComponent
            let fullPath = fileURL.path
            let relativePath = fullPath.replacingOccurrences(of: basePath + "/", with: "")

            // Skip if matches gitignore patterns
            if matchesGitignore(relativePath, patterns: gitignorePatterns) || matchesGitignore(fileName, patterns: gitignorePatterns) {
                continue
            }

            let result = FileSearchIndexResult(
                basePath: basePath,
                relativePath: relativePath,
                isDirectory: false
            )
            results.append(result)
        }

        return results
    }

    private func indexDirectoryWithGitLsFiles(_ path: String) async -> [FileSearchIndexResult]? {
        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["-C", path, "ls-files", "--cached", "--others", "--exclude-standard"]
            )

            guard result.succeeded else { return nil }

            let basePath = path
            var items: [FileSearchIndexResult] = []
            items.reserveCapacity(min(50_000, max(128, result.stdout.count / 48)))

            result.stdout.enumerateLines { line, _ in
                let rel = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rel.isEmpty else { return }
                items.append(FileSearchIndexResult(basePath: basePath, relativePath: rel, isDirectory: false))
            }

            return items
        } catch {
            return nil
        }
    }

    // Load gitignore patterns from .gitignore file (manual indexing fallback)
    private func loadGitignorePatterns(at path: String) -> [String] {
        // Start with common patterns that should always be ignored
        var gitignorePatterns: [String] = [
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

        return gitignorePatterns
    }

    // Check if path matches gitignore patterns - simplified matching
    private func matchesGitignore(_ path: String, patterns: [String]) -> Bool {
        let pathComponents = path.components(separatedBy: "/")

        for pattern in patterns {
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
    func search(query: String, in results: [FileSearchIndexResult], worktreePath: String, limit: Int = 200) async -> [FileSearchIndexResult] {
        guard !query.isEmpty else {
            // Return recent files when query is empty, or all results if no recent files
            let recent = getRecentFileResults(for: worktreePath, from: results)
            if !recent.isEmpty { return Array(recent.prefix(limit)) }
            return Array(results.prefix(limit))
        }

        let lowercaseQuery = query.lowercased()
        var scoredResults: [FileSearchIndexResult] = []
        scoredResults.reserveCapacity(min(limit * 4, 1000))

        for var result in results {
            let relativePath = result.relativePath.lowercased()
            let fileName = lastPathComponentLowercased(relativePath)

            // Score filename match (higher weight)
            let fileNameScore = fuzzyMatch(query: lowercaseQuery, target: fileName)

            // Score relative path match (lower weight)
            let pathScore = fuzzyMatch(query: lowercaseQuery, target: relativePath) * 0.6

            let totalScore = max(fileNameScore, pathScore)
            if totalScore > 0 {
                result.matchScore = totalScore
                scoredResults.append(result)
            }

            // Keep memory and sort cost bounded for very large repos.
            if scoredResults.count >= max(limit * 6, 600) {
                scoredResults.sort { $0.matchScore > $1.matchScore }
                scoredResults = Array(scoredResults.prefix(limit))
            }
        }

        // Sort by score (higher is better)
        scoredResults.sort { $0.matchScore > $1.matchScore }
        return Array(scoredResults.prefix(limit))
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
        cacheOrder.removeAll { $0 == path }
        recentFiles.removeValue(forKey: path)
    }

    // Clear all caches
    func clearAllCaches() {
        cachedResults.removeAll()
        cacheOrder.removeAll()
        recentFiles.removeAll()
    }

    // MARK: - Private Helpers

    private func touchCacheKey(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func evictCacheIfNeeded() {
        while cacheOrder.count > maxCachedDirectories {
            guard let evictKey = cacheOrder.first else { break }
            cacheOrder.removeFirst()
            cachedResults.removeValue(forKey: evictKey)
            recentFiles.removeValue(forKey: evictKey)
        }
    }

    private func lastPathComponentLowercased(_ path: String) -> String {
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }

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

        // Fuzzy matching (avoid O(n^2) String indexing)
        var targetIndex = target.startIndex
        while targetIndex < target.endIndex {
            let targetChar = target[targetIndex]
            if queryIndex < query.endIndex && targetChar == query[queryIndex] {
                // Base score for match
                score += 10.0

                // Bonus for consecutive matches
                if let last = lastMatchIndex, target.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += Double(consecutiveMatches) * 5.0
                } else {
                    consecutiveMatches = 0
                }

                // Bonus for matching start of word
                if targetIndex == target.startIndex {
                    score += 15.0
                } else {
                    let prev = target[target.index(before: targetIndex)]
                    if prev == "/" || prev == "." {
                        score += 15.0
                    }
                }

                // Uppercase bonus intentionally omitted here; the target is lowercased for speed.

                lastMatchIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            }

            targetIndex = target.index(after: targetIndex)
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
