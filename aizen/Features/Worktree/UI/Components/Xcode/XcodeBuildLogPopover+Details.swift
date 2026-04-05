//
//  XcodeBuildLogPopover+Details.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension XcodeBuildLogPopover {
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
