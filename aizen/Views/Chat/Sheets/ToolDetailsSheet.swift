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
    var agentSession: AgentSession?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(
                showsBackground: false,
                padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
            ) {
                Text("chat.tool.details.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            } trailing: {
                DetailCloseButton { dismiss() }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(toolCalls) { toolCall in
                        toolCallDetailView(toolCall)
                    }
                }
                .padding(12)
            }
        }
        .background(.ultraThinMaterial)
        .frame(width: 650, height: 550)
    }

    @ViewBuilder
    private func toolCallDetailView(_ toolCall: ToolCall) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                            if let line = loc.line {
                                Text("L\(line)")
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
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(toolCall.content.enumerated()), id: \.offset) { _, block in
                        ToolCallContentView(content: block, agentSession: agentSession)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.25))
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

// MARK: - Tool Call Content View

struct ToolCallContentView: View {
    let content: ToolCallContent
    var agentSession: AgentSession?

    var body: some View {
        switch content {
        case .content(let block):
            ContentBlockRenderer(block: block, style: .compact)
        case .diff(let diff):
            ToolCallDiffView(diff: diff)
        case .terminal(let terminal):
            TerminalOutputPreview(terminalId: terminal.terminalId, agentSession: agentSession)
        }
    }
}

// MARK: - Terminal Output Preview

struct TerminalOutputPreview: View {
    let terminalId: String
    var agentSession: AgentSession?

    @State private var output: String = ""
    @State private var isRunning: Bool = false
    private let maxDisplayChars = 20_000

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with terminal icon and status
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text("Terminal Output")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if isRunning {
                    HStack(spacing: 4) {
                        ScaledProgressView(size: 10)
                        Text("Running")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Terminal-like output area
            let displayOutput = output.count > maxDisplayChars
                ? String(output.suffix(maxDisplayChars))
                : output
            MonospaceTextPanel(
                text: displayOutput,
                emptyText: "No output yet...",
                maxHeight: 200,
                backgroundColor: Color(nsColor: .textBackgroundColor),
                showsBorder: true
            )
        }
        .task {
            await loadOutput()
        }
    }

    @MainActor
    private func loadOutput() async {
        guard let session = agentSession else { return }

        var exitedIterations = 0
        let gracePeriodIterations = 3 // Continue polling 3 more times after exit

        // Poll for output updates
        for _ in 0..<60 { // Poll for up to 30 seconds
            let newOutput = await session.getTerminalOutput(terminalId: terminalId) ?? ""
            let running = await session.isTerminalRunning(terminalId: terminalId)

            if newOutput != output || running != isRunning {
                output = newOutput
                isRunning = running
            }

            // If process exited, use grace period to catch any remaining output
            if !running {
                exitedIterations += 1
                // Exit after grace period OR if we have output
                if exitedIterations >= gracePeriodIterations || !newOutput.isEmpty {
                    break
                }
            }

            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
    }
}

// MARK: - Tool Call Diff View

struct ToolCallDiffView: View {
    let diff: ToolCallDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diff.path)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            MonospaceTextPanel(
                text: "",
                attributedText: diffAttributedText,
                maxHeight: 200,
                backgroundColor: Color(nsColor: .textBackgroundColor),
                padding: 8
            )
        }
    }

    private var diffAttributedText: AttributedString {
        var result = AttributedString()
        let font = Font.system(size: 11, design: .monospaced)

        if let oldText = diff.oldText {
            let oldLines = oldText.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in oldLines.enumerated() {
                var chunk = AttributedString("- \(line)")
                chunk.font = font
                chunk.foregroundColor = .red
                result.append(chunk)
                if index < oldLines.count - 1 || !diff.newText.isEmpty {
                    result.append(AttributedString("\n"))
                }
            }
        }

        let newLines = diff.newText.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in newLines.enumerated() {
            var chunk = AttributedString("+ \(line)")
            chunk.font = font
            chunk.foregroundColor = .green
            result.append(chunk)
            if index < newLines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        if result.characters.isEmpty {
            var placeholder = AttributedString(" ")
            placeholder.font = font
            result = placeholder
        }

        return result
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
        MonospaceTextPanel(
            text: text,
            maxHeight: 160,
            backgroundColor: Color(nsColor: .textBackgroundColor),
            padding: 6,
            showsBorder: true,
            borderColor: Color.gray.opacity(0.12),
            borderWidth: 0.5
        )
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
