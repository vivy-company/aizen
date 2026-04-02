//  InlineDiffView.swift
//  aizen
//
//  Inline diff view backed by VVDiffView
//

import ACP
import AppKit
import SwiftUI
import VVCode

struct InlineDiffView: View {
    let diff: ToolCallDiff
    var allowCompute: Bool = true

    @AppStorage(AppearanceSettings.codeFontFamilyKey) private var codeFontFamily = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.diffFontSizeKey) private var diffFontSize = AppearanceSettings.defaultDiffFontSize
    @Environment(\.colorScheme) private var colorScheme

    @State private var cachedDiffLines: [ChatDiffLine]?
    @State private var isComputing = false
    @State private var showFullDiff = false
    @State private var lastComputedDiffId: String?

    private let previewLineCount = 8
    private let previewRenderLineCap = 200
    private let largeDiffCharacterThreshold = 120_000
    private let largeDiffLineThreshold = 4_000

    private var diffId: String {
        "\(diff.path)-\(diff.oldText?.hashValue ?? 0)-\(diff.newText.hashValue)"
    }

    private var diffTaskId: String {
        allowCompute ? diffId : "diff-deferred-\(diff.path)"
    }

    private var diffLines: [ChatDiffLine] {
        cachedDiffLines ?? []
    }

    private var isDeletedFileDiff: Bool {
        guard let oldText = diff.oldText else { return false }
        return !oldText.isEmpty && diff.newText.isEmpty
    }

    private var hasMoreLines: Bool {
        diffLines.count > previewLineCount
    }

    private var previewDiffLines: [ChatDiffLine] {
        Array(diffLines.prefix(previewRenderLineCap))
    }

    private var previewHeight: CGFloat {
        let rowHeight = max(15, CGFloat(diffFontSize + 4))
        return CGFloat(previewLineCount) * rowHeight + 26
    }

    private var theme: VVTheme {
        AppearanceSettings.resolvedTheme(colorScheme: colorScheme)
    }

    private var configuration: VVConfiguration {
        let font = NSFont.monospacedSystemFont(ofSize: max(diffFontSize, 10), weight: .regular)

        return VVConfiguration.default
            .with(font: font)
            .with(showLineNumbers: true)
            .with(showGutter: true)
            .with(showGitGutter: false)
            .with(wrapLines: true)
    }

    private var unifiedDiffText: String {
        Self.buildUnifiedDiff(path: diff.path, lines: diffLines)
    }

    private var previewUnifiedDiffText: String {
        Self.buildUnifiedDiff(path: diff.path, lines: previewDiffLines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isDeletedFileDiff ? "trash" : "doc.badge.plus")
                    .font(.system(size: 9))
                Text(URL(fileURLWithPath: diff.path).lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                if !allowCompute {
                    Text("Diff will appear when the tool completes")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else if isComputing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Computing diff...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else if isDeletedFileDiff {
                    deletedFilePlaceholder
                } else {
                    VVDiffView(unifiedDiff: previewUnifiedDiffText)
                        .theme(theme)
                        .configuration(configuration)
                        .renderStyle(.inline)
                        .syntaxHighlighting(true)
                        .frame(height: previewHeight)

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
        .task(id: diffTaskId) {
            await computeDiffAsync()
        }
        .sheet(isPresented: $showFullDiff) {
                FullDiffSheet(
                    diff: diff,
                    unifiedDiffText: unifiedDiffText,
                    fontFamily: codeFontFamily,
                    fontSize: diffFontSize
                )
            }
    }

    private var deletedFilePlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("File removed. Diff content omitted.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func computeDiffAsync() async {
        guard allowCompute else { return }

        if lastComputedDiffId != diffId {
            cachedDiffLines = nil
        }

        guard cachedDiffLines == nil else { return }
        lastComputedDiffId = diffId

        if isDeletedFileDiff {
            cachedDiffLines = []
            isComputing = false
            return
        }

        isComputing = true

        let oldText = diff.oldText
        let newText = diff.newText
        let oldLineCount = oldText?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        let newLineCount = newText.split(separator: "\n", omittingEmptySubsequences: false).count
        let combinedCharacters = (oldText?.count ?? 0) + newText.count
        let isLargeDiff = combinedCharacters > largeDiffCharacterThreshold || (oldLineCount + newLineCount) > largeDiffLineThreshold

        let lines = await Task.detached(priority: .userInitiated) {
            if isLargeDiff {
                return InlineDiffComputer.computeUnifiedDiff(
                    oldText: oldText,
                    newText: newText,
                    contextLines: 1,
                    maxOutputLines: 600
                )
            }
            return InlineDiffComputer.computeUnifiedDiff(
                oldText: oldText,
                newText: newText,
                contextLines: 3,
                maxOutputLines: 2_000
            )
        }.value

        cachedDiffLines = lines
        isComputing = false
    }

    private static func buildUnifiedDiff(path: String, lines: [ChatDiffLine]) -> String {
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

private nonisolated enum InlineDiffComputer {
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

// MARK: - Full Diff Sheet

private struct FullDiffSheet: View {
    @Environment(\.dismiss) private var dismiss

    let diff: ToolCallDiff
    let unifiedDiffText: String
    let fontFamily: String
    let fontSize: Double

    @Environment(\.colorScheme) private var colorScheme

    private var theme: VVTheme {
        AppearanceSettings.resolvedTheme(colorScheme: colorScheme)
    }

    private var configuration: VVConfiguration {
        let font = NSFont.monospacedSystemFont(ofSize: max(fontSize, 10), weight: .regular)

        return VVConfiguration.default
            .with(font: font)
            .with(showLineNumbers: true)
            .with(showGutter: true)
            .with(showGitGutter: false)
            .with(wrapLines: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(
                showsBackground: false,
                padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diff")
                        .font(.headline)
                    Text(diff.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } trailing: {
                DetailCloseButton { dismiss() }
            }

            Divider()

            VVDiffView(unifiedDiff: unifiedDiffText)
                .theme(theme)
                .configuration(configuration)
                .renderStyle(.inline)
                .syntaxHighlighting(true)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
    }
}

nonisolated private enum ChatDiffLineType: Sendable {
    case context
    case added
    case deleted
    case separator
}

nonisolated private struct ChatDiffLine: Identifiable, Sendable {
    let id = UUID()
    let type: ChatDiffLineType
    let content: String
}
