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

    @AppStorage(AppearanceSettings.codeFontFamilyKey) var codeFontFamily = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.diffFontSizeKey) var diffFontSize = AppearanceSettings.defaultDiffFontSize
    @Environment(\.colorScheme) private var colorScheme

    @State var cachedDiffLines: [ChatDiffLine]?
    @State var isComputing = false
    @State var showFullDiff = false
    @State var lastComputedDiffId: String?

    let previewLineCount = 8
    let previewRenderLineCap = 200
    let largeDiffCharacterThreshold = 120_000
    let largeDiffLineThreshold = 4_000

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

}
