//
//  DiffView+PathNormalization.swift
//  aizen
//

import Foundation

extension DiffView {
    static func normalizeDiffPaths(in diff: String, repoPath: String) -> String {
        guard !repoPath.isEmpty else {
            return diff
        }

        let standardizedRepoPath = URL(fileURLWithPath: repoPath).standardizedFileURL.path
        guard !standardizedRepoPath.isEmpty else {
            return diff
        }

        let normalizedLines = diff.components(separatedBy: .newlines).map { line in
            if line.hasPrefix("diff --git ") {
                return normalizeDiffGitHeader(line, repoPath: standardizedRepoPath)
            }
            if line.hasPrefix("--- ") {
                let value = String(line.dropFirst(4))
                let normalized = normalizePathToken(value, repoPath: standardizedRepoPath)
                return "--- \(normalized)"
            }
            if line.hasPrefix("+++ ") {
                let value = String(line.dropFirst(4))
                let normalized = normalizePathToken(value, repoPath: standardizedRepoPath)
                return "+++ \(normalized)"
            }
            return line
        }

        return normalizedLines.joined(separator: "\n")
    }

    static func normalizeDiffGitHeader(_ line: String, repoPath: String) -> String {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count >= 4 else {
            return line
        }

        let leftPath = normalizePathToken(String(parts[2]), repoPath: repoPath)
        let rightPath = normalizePathToken(String(parts[3]), repoPath: repoPath)
        return "diff --git \(leftPath) \(rightPath)"
    }

    static func normalizePathToken(_ token: String, repoPath: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "/dev/null" {
            return trimmed
        }

        let prefix: String
        let rawPath: String
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            prefix = String(trimmed.prefix(2))
            rawPath = String(trimmed.dropFirst(2))
        } else {
            prefix = ""
            rawPath = trimmed
        }

        let standardizedPath: String
        if rawPath.hasPrefix("/") {
            standardizedPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        } else {
            standardizedPath = rawPath
        }

        let relativePath: String
        if standardizedPath == repoPath {
            relativePath = "."
        } else if standardizedPath.hasPrefix(repoPath + "/") {
            relativePath = String(standardizedPath.dropFirst(repoPath.count + 1))
        } else {
            relativePath = rawPath
        }

        if prefix.isEmpty {
            return relativePath
        }
        return "\(prefix)\(relativePath)"
    }
}
