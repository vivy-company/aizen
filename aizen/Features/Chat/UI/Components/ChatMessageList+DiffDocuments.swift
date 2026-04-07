//
//  ChatMessageList+DiffDocuments.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import ACP
import Foundation

extension ChatMessageList {
    func unifiedDiffDocument(for diff: ToolCallDiff) -> String {
        diffDocument(for: diff, contextLines: 3, maxOutputLines: 8_000)
    }

    func diffDocument(for diff: ToolCallDiff, contextLines: Int, maxOutputLines: Int) -> String {
        let normalizedPath = normalizedDiffPath(diff.path)
        let oldText = diff.oldText ?? ""
        let oldLines = oldText.isEmpty ? [String]() : oldText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = diff.newText.isEmpty ? [String]() : diff.newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let linePairs = unifiedDiffLines(
            oldLines: oldLines,
            newLines: newLines,
            contextLines: contextLines,
            maxOutputLines: maxOutputLines
        )

        var output: [String] = [
            "diff --git a/\(normalizedPath) b/\(normalizedPath)",
            "--- a/\(normalizedPath)",
            "+++ b/\(normalizedPath)"
        ]

        output.append("@@ -1,1 +1,1 @@")

        if linePairs.isEmpty {
            output.append(" ")
            return output.joined(separator: "\n")
        }

        for line in linePairs {
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

    func normalizedDiffPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "file" }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if !expanded.hasPrefix("/") {
            return expanded
        }

        let cwd = FileManager.default.currentDirectoryPath
        if expanded.hasPrefix(cwd + "/") {
            return String(expanded.dropFirst(cwd.count + 1))
        }

        let pathURL = URL(fileURLWithPath: expanded)
        let components = pathURL.pathComponents.filter { $0 != "/" }
        if components.count >= 3 {
            return components.suffix(3).joined(separator: "/")
        }
        return pathURL.lastPathComponent.isEmpty ? expanded : pathURL.lastPathComponent
    }

    func unifiedDiffLines(
        oldLines: [String],
        newLines: [String],
        contextLines: Int,
        maxOutputLines: Int
    ) -> [ToolDiffPreviewLine] {
        if oldLines == newLines {
            return []
        }

        let complexityLimit = 350_000
        let complexity = oldLines.count * newLines.count
        if complexity > complexityLimit {
            return fastUnifiedDiffLines(oldLines: oldLines, newLines: newLines, maxOutputLines: maxOutputLines)
        }

        let lcs = longestCommonSubsequence(oldLines, newLines)
        var edits: [(type: ToolDiffPreviewLineType, content: String)] = []
        edits.reserveCapacity(oldLines.count + newLines.count)

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

        return hunkedDiffLines(edits: edits, contextLines: contextLines, maxOutputLines: maxOutputLines)
    }

    func fastUnifiedDiffLines(
        oldLines: [String],
        newLines: [String],
        maxOutputLines: Int
    ) -> [ToolDiffPreviewLine] {
        var result: [ToolDiffPreviewLine] = []
        result.reserveCapacity(min(maxOutputLines + 1, oldLines.count + newLines.count))

        let oldLimit = min(oldLines.count, maxOutputLines / 2)
        let newLimit = min(newLines.count, maxOutputLines - oldLimit)

        for line in oldLines.prefix(oldLimit) {
            result.append(ToolDiffPreviewLine(type: .deleted, content: line))
        }
        for line in newLines.prefix(newLimit) {
            result.append(ToolDiffPreviewLine(type: .added, content: line))
        }

        if oldLines.count > oldLimit || newLines.count > newLimit {
            result.append(ToolDiffPreviewLine(type: .separator, content: "… truncated …"))
        }

        return result
    }

    func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let maxMatrixSize = 900
        if a.count > maxMatrixSize || b.count > maxMatrixSize {
            return simpleLCS(a, b)
        }

        let rows = a.count + 1
        let cols = b.count + 1
        var dp = Array(repeating: Array(repeating: 0, count: cols), count: rows)

        for i in 1..<rows {
            for j in 1..<cols {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [String] = []
        var i = a.count
        var j = b.count
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

    func simpleLCS(_ a: [String], _ b: [String]) -> [String] {
        let bSet = Set(b)
        return a.filter { bSet.contains($0) }
    }

    func hunkedDiffLines(
        edits: [(type: ToolDiffPreviewLineType, content: String)],
        contextLines: Int,
        maxOutputLines: Int
    ) -> [ToolDiffPreviewLine] {
        var changeIndices: [Int] = []
        for (index, edit) in edits.enumerated() where edit.type != .context {
            changeIndices.append(index)
        }
        guard !changeIndices.isEmpty else { return [] }

        var hunks: [[Int]] = []
        var current: [Int] = []
        for index in changeIndices {
            if current.isEmpty {
                current = [index]
            } else if index - (current.last ?? index) <= (contextLines * 2 + 1) {
                current.append(index)
            } else {
                hunks.append(current)
                current = [index]
            }
        }
        if !current.isEmpty {
            hunks.append(current)
        }

        var result: [ToolDiffPreviewLine] = []
        result.reserveCapacity(min(maxOutputLines + hunks.count, edits.count))

        for (hunkIndex, hunk) in hunks.enumerated() {
            let start = max(0, (hunk.first ?? 0) - contextLines)
            let end = min(edits.count - 1, (hunk.last ?? 0) + contextLines)

            if hunkIndex > 0 {
                result.append(ToolDiffPreviewLine(type: .separator, content: "···"))
            }

            for index in start...end {
                result.append(ToolDiffPreviewLine(type: edits[index].type, content: edits[index].content))
                if result.count >= maxOutputLines {
                    result.append(ToolDiffPreviewLine(type: .separator, content: "… truncated …"))
                    return result
                }
            }
        }

        return result
    }
}
