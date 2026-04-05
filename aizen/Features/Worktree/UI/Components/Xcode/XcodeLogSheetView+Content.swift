//
//  XcodeLogSheetView+Content.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension XcodeLogSheetView {
    var header: some View {
        DetailHeaderBar(showsBackground: false) {
            Label("Debug Logs", systemImage: "text.alignleft")
                .font(.headline)
        } trailing: {
            HStack(spacing: 12) {
                if buildManager.isLogStreamActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Streaming")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                Button("Clear") {
                    buildManager.clearLogs()
                }

                Button("Copy") {
                    let text = buildManager.logOutput.joined(separator: "\n")
                    Clipboard.copy(text)
                }

                DetailCloseButton(action: { dismiss() }, size: 16)
            }
            .buttonStyle(.borderless)
        }
    }

    var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(buildManager.logOutput.enumerated()), id: \.offset) { index, line in
                        LogLineView(line: line)
                            .id(index)
                    }

                    if buildManager.logOutput.isEmpty {
                        Text("Waiting for logs...")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .task(id: buildManager.logOutput.count) {
                if autoScroll {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    var footer: some View {
        HStack {
            if let bundleId = buildManager.launchedBundleId {
                Text(bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if buildManager.isLogStreamActive {
                Button("Stop") {
                    buildManager.stopLogStream()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Start") {
                    buildManager.startLogStream()
                }
                .buttonStyle(.borderedProminent)
                .disabled(buildManager.launchedBundleId == nil)
            }
        }
        .padding()
    }
}

struct LogLineView: View {
    let line: String

    var body: some View {
        Text(line)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .foregroundStyle(lineColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineColor: Color {
        if line.lowercased().contains("error") {
            return .red
        } else if line.lowercased().contains("warning") {
            return .orange
        } else if line.lowercased().contains("debug") {
            return .secondary
        }
        return .primary
    }
}
