//
//  XcodeBuildLogPopover+Content.swift
//  aizen
//

import SwiftUI

extension XcodeBuildLogPopover {
    var buildErrorMarkdown: String {
        """
        ## Xcode Build Error

        The build failed with the following errors:

        ```
        \(log)
        ```

        Please help me fix these build errors.
        """
    }

    @ViewBuilder
    var logContent: some View {
        if log.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                        let text = String(line)
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color(for: text))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if truncatedLines {
                        Text("… truncated, showing first \(displayLines.count) of \(totalLines) lines")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    @ViewBuilder
    var emptyState: some View {
        VStack {
            Spacer()
            Text("No build log available")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var fullLogSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Full Build Log")
                    .font(.headline)
                Spacer()
                Button("Copy All") { copyToClipboard() }
                    .disabled(log.isEmpty)
                Button("Close") { showFullLog = false }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(fullLines.indices, id: \.self) { idx in
                        let line = fullLines[idx]
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    var fullLines: [String] { lines }

    var totalLines: Int {
        fullLines.count
    }

    var displayLines: ArraySlice<String> {
        fullLines.prefix(maxPreviewLines)
    }

    var truncatedLines: Bool {
        totalLines > maxPreviewLines
    }

    var maxPreviewLines: Int { 600 }

    func color(for line: String) -> Color {
        if line.contains("error:") {
            return .red
        } else if line.contains("warning:") {
            return .orange
        } else {
            return .primary
        }
    }
}
