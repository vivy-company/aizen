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
