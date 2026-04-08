//  InlineDiffFullSheet.swift
//  aizen
//

import ACP
import AppKit
import SwiftUI
import VVCode

struct FullDiffSheet: View {
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
