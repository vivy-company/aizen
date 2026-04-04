//
//  FileSearchService.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation

nonisolated struct FileSearchIndexResult: Identifiable, Sendable {
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
    var recentFiles: [String: [String]] = [:]
    let maxRecentFiles = 10

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
        } else if let nestedGitResults = await indexDirectoryFromNestedGitRepositories(path) {
            results = nestedGitResults
        } else {
            results = await indexDirectoryManually(path)
        }

        // Cache results
        cachedResults[path] = results
        touchCacheKey(path)
        evictCacheIfNeeded()
        return results
    }

    // Cross-project roots are directories of repo symlinks.
    // Index each linked repo with git-aware search and remap paths under the root.
    private func indexDirectoryFromNestedGitRepositories(_ path: String) async -> [FileSearchIndexResult]? {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: path)

        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return nil
        }

        var indexedAnyRepository = false
        var merged: [FileSearchIndexResult] = []
        var seenRelativePaths = Set<String>()

        for childURL in children {
            if let values = try? childURL.resourceValues(forKeys: [.isHiddenKey]),
               values.isHidden == true {
                continue
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let childPath = childURL.path
            let childGitPath = (childPath as NSString).appendingPathComponent(".git")
            guard fileManager.fileExists(atPath: childGitPath) else {
                continue
            }

            let childRelativePrefix = childURL.lastPathComponent
            let childEntries: [FileSearchIndexResult]
            if let gitEntries = await indexDirectoryWithGitLsFiles(childPath) {
                childEntries = gitEntries
            } else {
                childEntries = await indexDirectoryManually(childPath)
            }

            indexedAnyRepository = true

            for entry in childEntries {
                let mappedRelativePath = "\(childRelativePrefix)/\(entry.relativePath)"
                if seenRelativePaths.insert(mappedRelativePath).inserted {
                    merged.append(
                        FileSearchIndexResult(
                            basePath: path,
                            relativePath: mappedRelativePath,
                            isDirectory: false
                        )
                    )
                }
            }
        }

        guard indexedAnyRepository else {
            return nil
        }

        return merged
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
            let cleanPattern = pattern
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

}
