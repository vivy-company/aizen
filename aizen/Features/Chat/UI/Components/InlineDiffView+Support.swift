//
//  InlineDiffView+Support.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import Foundation

extension InlineDiffView {
    static func buildUnifiedDiff(path: String, lines: [ChatDiffLine]) -> String {
        let normalizedPath = path.isEmpty ? "file" : path
        var output: [String] = [
            "diff --git a/\(normalizedPath) b/\(normalizedPath)",
            "--- a/\(normalizedPath)",
            "+++ b/\(normalizedPath)",
            "@@ -1,1 +1,1 @@"
        ]

        if lines.isEmpty {
            output.append(" ")
            return output.joined(separator: "\n")
        }

        for line in lines {
            switch line.type {
            case .context:
                output.append(" \(line.content)")
            case .added:
                output.append("+\(line.content)")
            case .deleted:
                output.append("-\(line.content)")
            case .separator:
                output.append("@@ -1,1 +1,1 @@")
            }
        }

        return output.joined(separator: "\n")
    }
}

// MARK: - Diff Computation

nonisolated enum InlineDiffComputer {
    static func computeUnifiedDiff(
        oldText: String?,
        newText: String,
        contextLines: Int = 3,
        maxOutputLines: Int = 2_000
    ) -> [ChatDiffLine] {
        let oldLines = (oldText ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let lcs = longestCommonSubsequence(oldLines, newLines)

        var edits: [(type: ChatDiffLineType, content: String)] = []
        var oldIdx = 0
        var newIdx = 0
        var lcsIdx = 0

        while oldIdx < oldLines.count || newIdx < newLines.count {
            if lcsIdx < lcs.count && oldIdx < oldLines.count && newIdx < newLines.count &&
                oldLines[oldIdx] == lcs[lcsIdx] && newLines[newIdx] == lcs[lcsIdx] {
                edits.append((.context, oldLines[oldIdx]))
                oldIdx += 1
                newIdx += 1
                lcsIdx += 1
            } else if oldIdx < oldLines.count && (lcsIdx >= lcs.count || oldLines[oldIdx] != lcs[lcsIdx]) {
                edits.append((.deleted, oldLines[oldIdx]))
                oldIdx += 1
            } else if newIdx < newLines.count {
                edits.append((.added, newLines[newIdx]))
                newIdx += 1
            }
        }

        return generateHunks(edits: edits, contextLines: contextLines, maxOutputLines: maxOutputLines)
    }

    static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        guard m > 0 && n > 0 else { return [] }

        let maxLCSSize = 1000
        if m * n > maxLCSSize * maxLCSSize {
            return simpleLCS(a, b)
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [String] = []
        var i = m
        var j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    static func simpleLCS(_ a: [String], _ b: [String]) -> [String] {
        let bSet = Set(b)
        return a.filter { bSet.contains($0) }
    }

    static func generateHunks(
        edits: [(type: ChatDiffLineType, content: String)],
        contextLines: Int,
        maxOutputLines: Int
    ) -> [ChatDiffLine] {
        var result: [ChatDiffLine] = []

        var changeIndices: [Int] = []
        for (i, edit) in edits.enumerated() {
            if edit.type != .context {
                changeIndices.append(i)
            }
        }

        if changeIndices.isEmpty {
            return []
        }

        var hunks: [[Int]] = []
        var currentHunk: [Int] = []

        for idx in changeIndices {
            if currentHunk.isEmpty {
                currentHunk.append(idx)
            } else if idx - currentHunk.last! <= contextLines * 2 + 1 {
                currentHunk.append(idx)
            } else {
                hunks.append(currentHunk)
                currentHunk = [idx]
            }
        }
        if !currentHunk.isEmpty {
            hunks.append(currentHunk)
        }

        for (hunkIdx, hunk) in hunks.enumerated() {
            let startIdx = max(0, hunk.first! - contextLines)
            let endIdx = min(edits.count - 1, hunk.last! + contextLines)

            if hunkIdx > 0 {
                result.append(ChatDiffLine(type: .separator, content: "···"))
            }

            for i in startIdx...endIdx {
                let edit = edits[i]
                result.append(ChatDiffLine(type: edit.type, content: edit.content))
                if result.count >= maxOutputLines {
                    result.append(ChatDiffLine(type: .separator, content: "… truncated …"))
                    return result
                }
            }
        }

        return result
    }
}

nonisolated enum ChatDiffLineType: Sendable {
    case context
    case added
    case deleted
    case separator
}

nonisolated struct ChatDiffLine: Identifiable, Sendable {
    let id = UUID()
    let type: ChatDiffLineType
    let content: String
}
