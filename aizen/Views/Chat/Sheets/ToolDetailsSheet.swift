//
//  ToolDetailsSheet.swift
//  aizen
//
//  Tool details display dialog
//

import SwiftUI
import Foundation

struct ToolDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let toolCalls: [ToolCall]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("chat.tool.details.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(toolCalls) { toolCall in
                        toolCallDetailView(toolCall)
                    }
                }
                .padding(16)
            }
        }
        .background(.ultraThinMaterial)
        .frame(width: 650, height: 550)
    }

    @ViewBuilder
    private func toolCallDetailView(_ toolCall: ToolCall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor(for: toolCall.status))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(toolCall.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(statusLabel(for: toolCall.status))
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor(for: toolCall.status))
                }
                Spacer()
            }

            if let locations = toolCall.locations, !locations.isEmpty {
                SectionHeader(title: "Files")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(locations.enumerated()), id: \.offset) { _, loc in
                        HStack(spacing: 6) {
                            Text(loc.path ?? "unknown")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if let start = loc.startLine {
                                Text("L\(start)\(loc.endLine != nil ? "–\(loc.endLine!)" : "")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let rawInput = toolCall.rawInput {
                SectionHeader(title: "Input")
                JsonBlockView(text: stringify(rawInput))
            }

            if let rawOutput = toolCall.rawOutput {
                SectionHeader(title: "Output")
                JsonBlockView(text: stringify(rawOutput))
            }

            if !toolCall.content.isEmpty {
                SectionHeader(title: "Text Output")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(toolCall.content.enumerated()), id: \.offset) { _, block in
                        CompactContentBlockView(block: block)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.35))
        .cornerRadius(8)
    }

    private func statusColor(for status: ToolStatus) -> Color {
        switch status {
        case .pending: return .yellow
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func statusLabel(for status: ToolStatus) -> String {
        switch status {
        case .pending: return String(localized: "chat.status.pending")
        case .inProgress: return String(localized: "chat.tool.status.running")
        case .completed: return String(localized: "chat.tool.status.done")
        case .failed: return String(localized: "chat.tool.status.failed")
        }
    }

}

// MARK: - Compact Content Block View

struct CompactContentBlockView: View {
    let block: ContentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch block {
            case .text(let content):
                ScrollView([.horizontal, .vertical]) {
                    Text(content.text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

            case .image(let content):
                Text(String(localized: "chat.content.imageType \(content.mimeType)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .resource(let content):
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "chat.content.resourceUri \(content.resource.uri)"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let text = content.resource.text {
                        ScrollView([.horizontal, .vertical]) {
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                    }
                }

            case .audio(let content):
                Text(String(localized: "chat.content.audioType \(content.mimeType)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .embeddedResource(let content):
                Text(String(localized: "chat.content.resourceUri \(content.uri)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            case .diff(let content):
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let path = content.path {
                            Text(String(localized: "chat.content.file \(path)"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                        }

                        let diffText = "--- \(content.path ?? "original")\n+++ \(content.path ?? "modified")\n\(content.oldText)\n\(content.newText)"
                        ForEach(diffText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(diffLineColor(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

            case .terminalEmbed(let content):
                ScrollView([.horizontal, .vertical]) {
                    Text(content.output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color.black.opacity(0.8))
                .cornerRadius(4)
                .foregroundStyle(.white)
            }
        }
    }

    private func diffLineColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .blue
        }
        return .primary
    }
}

// MARK: - Helpers

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JsonBlockView: View {
    let text: String
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(4)
    }
}

private func stringify(_ any: AnyCodable) -> String {
    // If the raw value is already a String, try to pretty-print if JSON
    if let str = any.value as? String {
        if let data = str.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
           let out = String(data: pretty, encoding: .utf8) {
            return out
        }
        return str
    }

    if let data = try? JSONEncoder().encode(any),
       let obj = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
       let string = String(data: pretty, encoding: .utf8) {
        return string
    }
    return String(describing: any.value)
}
