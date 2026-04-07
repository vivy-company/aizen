//
//  ANSILazyLogView.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import SwiftUI

// MARK: - Lazy ANSI Log View

struct ANSILazyLogView: View {
    let logs: String
    let fontSize: CGFloat

    @State private var parsedLines: [ANSIParsedLine] = []
    @State private var isProcessing = true

    init(_ logs: String, fontSize: CGFloat = 11) {
        self.logs = logs
        self.fontSize = fontSize
    }

    var body: some View {
        Group {
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing logs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else if parsedLines.isEmpty {
                Text("No logs available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { _ in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(parsedLines) { line in
                                Text(line.attributedString)
                                    .font(.system(size: fontSize, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(12)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .task(id: logs) {
            await parseLogsAsync(logs)
        }
    }

    @MainActor
    private func parseLogsAsync(_ text: String) async {
        isProcessing = true
        defer {
            isProcessing = false
        }

        let parsed = await Task.detached(priority: .userInitiated) {
            ANSIParser.parseLines(text)
        }
        .value

        guard !Task.isCancelled else { return }
        parsedLines = parsed
    }
}
