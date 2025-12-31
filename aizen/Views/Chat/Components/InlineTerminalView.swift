//  InlineTerminalView.swift
//  aizen
//
//  Inline terminal output view with ANSI color support
//

import SwiftUI

struct InlineTerminalView: View {
    let terminalId: String
    var agentSession: AgentSession?

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var loadTask: Task<Void, Never>?
    private let maxDisplayChars = 20_000

    private var fontSize: CGFloat {
        max(terminalFontSize - 2, 9) // Slightly smaller for inline view
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Terminal output with ANSI colors
            ScrollView {
                let displayOutput = output.count > maxDisplayChars
                    ? String(output.suffix(maxDisplayChars))
                    : output
                if displayOutput.isEmpty {
                    Text("Waiting for output...")
                        .font(.custom(terminalFontName, size: fontSize))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(ANSIParser.parse(displayOutput))
                        .font(.custom(terminalFontName, size: fontSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(Color(red: 0.11, green: 0.11, blue: 0.13))
            .cornerRadius(6)

            // Running indicator below
            if isRunning {
                HStack(spacing: 4) {
                    ScaledProgressView(size: 12)
                    Text("Running...")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            startLoading()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func startLoading() {
        // Cancel any existing task before starting new one
        loadTask?.cancel()

        loadTask = Task { [weak agentSession] in
            guard let session = agentSession else { return }

            var exitedIterations = 0
            let gracePeriodIterations = 3 // Continue polling 3 more times after exit

            // Poll for output with cancellation support
            for _ in 0..<120 { // 60 seconds max
                if Task.isCancelled { break }

                let terminalOutput = await session.getTerminalOutput(terminalId: terminalId) ?? ""
                let running = await session.isTerminalRunning(terminalId: terminalId)

                let currentOutput = await MainActor.run { output }
                let currentRunning = await MainActor.run { isRunning }

                if terminalOutput != currentOutput || running != currentRunning {
                    await MainActor.run {
                        output = terminalOutput
                        isRunning = running
                    }
                }

                // If process exited, use grace period to catch any remaining output
                if !running {
                    exitedIterations += 1
                    // Exit after grace period OR if we have output
                    if exitedIterations >= gracePeriodIterations || !terminalOutput.isEmpty {
                        break
                    }
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
