//  InlineDiffView.swift
//  aizen
//
//  Inline diff view with syntax highlighting
//

import SwiftUI

struct InlineDiffView: View {
    let diff: ToolCallDiff

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    @State private var cachedDiffLines: [ChatDiffLine]?
    @State private var isComputing: Bool = false
    @State private var showFullDiff: Bool = false

    private let previewLineCount = 8

    private var fontSize: CGFloat {
        max(terminalFontSize - 2, 9)
    }

    private var diffId: String {
        "\(diff.path)-\(diff.oldText?.hashValue ?? 0)-\(diff.newText.hashValue)"
    }

    private var diffLines: [ChatDiffLine] {
        cachedDiffLines ?? []
    }

    private var hasMoreLines: Bool {
        diffLines.count > previewLineCount
    }

    private var previewLines: [ChatDiffLine] {
        if hasMoreLines {
            return Array(diffLines.prefix(previewLineCount))
        }
        return diffLines
    }
    
    private var previewHeight: CGFloat {
        let lineHeight = max(fontSize + 4, 14)
        return CGFloat(previewLines.count) * lineHeight + 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // File path header
            HStack(spacing: 4) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 9))
                Text(URL(fileURLWithPath: diff.path).lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)

            // Diff content with multiline selection support
            VStack(alignment: .leading, spacing: 0) {
                if isComputing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Computing diff...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else if !previewLines.isEmpty {
                    SelectableDiffView(
                        lines: previewLines,
                        fontSize: fontSize,
                        fontFamily: terminalFontName
                    )
                    .frame(height: previewHeight)

                    // Show more button
                    if hasMoreLines {
                        Button {
                            showFullDiff = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("···")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                Text("\(diffLines.count - previewLineCount) more lines")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .task(id: diffId) {
            await computeDiffAsync()
        }
        .sheet(isPresented: $showFullDiff) {
            FullDiffSheet(diff: diff, diffLines: diffLines, terminalFontName: terminalFontName, fontSize: fontSize)
        }
    }
    
    // MARK: - Async Diff Computation
    
    private func computeDiffAsync() async {
        guard cachedDiffLines == nil else { return }
        
        isComputing = true
        
        let oldText = diff.oldText
        let newText = diff.newText
        
        let lines = await Task.detached(priority: .userInitiated) {
            self.computeUnifiedDiff(oldText: oldText, newText: newText)
        }.value
        
        cachedDiffLines = lines
        isComputing = false
    }

    // MARK: - Diff Computation

    private func computeUnifiedDiff(oldText: String?, newText: String, contextLines: Int = 3) -> [ChatDiffLine] {
        let oldLines = (oldText ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Compute LCS to find matching lines
        let lcs = longestCommonSubsequence(oldLines, newLines)

        // Build edit script
        var edits: [(type: ChatDiffLineType, content: String)] = []
        var oldIdx = 0
        var newIdx = 0
        var lcsIdx = 0

        while oldIdx < oldLines.count || newIdx < newLines.count {
            if lcsIdx < lcs.count && oldIdx < oldLines.count && newIdx < newLines.count &&
               oldLines[oldIdx] == lcs[lcsIdx] && newLines[newIdx] == lcs[lcsIdx] {
                // Matching line (context)
                edits.append((.context, oldLines[oldIdx]))
                oldIdx += 1
                newIdx += 1
                lcsIdx += 1
            } else if oldIdx < oldLines.count && (lcsIdx >= lcs.count || oldLines[oldIdx] != lcs[lcsIdx]) {
                // Line removed from old
                edits.append((.deleted, oldLines[oldIdx]))
                oldIdx += 1
            } else if newIdx < newLines.count {
                // Line added in new
                edits.append((.added, newLines[newIdx]))
                newIdx += 1
            }
        }

        // Generate unified diff with context
        return generateHunks(edits: edits, contextLines: contextLines)
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        guard m > 0 && n > 0 else { return [] }

        // For very large diffs, use a simpler line-by-line comparison
        // to avoid O(n²) memory/time complexity
        let maxLCSSize = 1000
        if m * n > maxLCSSize * maxLCSSize {
            // Fallback: simple line matching for very large diffs
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

        // Backtrack to find LCS
        var result: [String] = []
        var i = m, j = n
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

    /// Simple LCS for large files - only matches exact consecutive sequences
    private func simpleLCS(_ a: [String], _ b: [String]) -> [String] {
        var bSet = Set(b)
        return a.filter { bSet.contains($0) }
    }

    private func generateHunks(edits: [(type: ChatDiffLineType, content: String)], contextLines: Int) -> [ChatDiffLine] {
        var result: [ChatDiffLine] = []

        // Find ranges of changes
        var changeIndices: [Int] = []
        for (i, edit) in edits.enumerated() {
            if edit.type != .context {
                changeIndices.append(i)
            }
        }

        if changeIndices.isEmpty {
            return [] // No changes
        }

        // Group changes into hunks
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

        // Generate output for each hunk
        for (hunkIdx, hunk) in hunks.enumerated() {
            let startIdx = max(0, hunk.first! - contextLines)
            let endIdx = min(edits.count - 1, hunk.last! + contextLines)

            // Add separator between hunks
            if hunkIdx > 0 {
                result.append(ChatDiffLine(type: .separator, content: "···"))
            }

            // Add lines in this hunk
            for i in startIdx...endIdx {
                let edit = edits[i]
                result.append(ChatDiffLine(type: edit.type, content: edit.content))
            }
        }

        return result
    }
}

// MARK: - Full Diff Sheet

private struct FullDiffSheet: View {
    @Environment(\.dismiss) private var dismiss

    let diff: ToolCallDiff
    let diffLines: [ChatDiffLine]
    let terminalFontName: String
    let fontSize: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diff")
                        .font(.headline)
                    Text(diff.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Full diff content with multiline selection
            SelectableDiffView(
                lines: diffLines,
                fontSize: fontSize,
                fontFamily: terminalFontName
            )
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
    }
}
