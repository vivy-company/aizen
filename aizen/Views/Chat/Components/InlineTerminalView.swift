//  InlineTerminalView.swift
//  aizen
//
//  Inline terminal output view with command block styling and ANSI color support
//

import SwiftUI

struct InlineTerminalView: View {
    let terminalId: String
    var agentSession: AgentSession?
    var command: String?
    var exitCode: Int?

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalThemeName") private var themeName = "Aizen Dark"
    @Environment(\.colorScheme) private var colorScheme

    @State private var output: String = ""
    @State private var isRunning: Bool = true
    @State private var loadTask: Task<Void, Never>?
    @State private var isExpanded: Bool = true
    @State private var isHovering: Bool = false

    private var theme: TerminalThemeProvider {
        TerminalThemeProvider(themeName: themeName)
    }
    
    private var fontSize: CGFloat {
        max(terminalFontSize - 2, 9)
    }
    
    private var trimmedOutput: String {
        TerminalOutputDefaults.trimmedOutput(output)
    }
    
    private var hasOutput: Bool {
        !trimmedOutput.isEmpty
    }
    
    private var resolvedExitCode: ExitCodeStatus {
        if isRunning { return .running }
        if let code = exitCode {
            return code == 0 ? .success : .failure(code: code)
        }
        return hasOutput ? .success : .unknown
    }
    
    private var exitCodeColor: Color {
        resolvedExitCode.color(provider: theme)
    }
    
    private var accentColor: Color {
        switch resolvedExitCode {
        case .success: return theme.ansiGreen
        case .failure: return theme.ansiRed
        case .running: return theme.ansiYellow
        case .unknown: return theme.ansiYellow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            if isExpanded {
                Divider()
                    .opacity(0.5)
                
                outputView
            }
        }
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.borderColor, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6)
                .fill(accentColor)
                .frame(width: 3)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06),
            radius: isHovering ? 4 : 2,
            x: 0,
            y: 1
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onAppear {
            startLoading()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.promptColor)
            
            if let cmd = command, !cmd.isEmpty {
                Text("$")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.promptColor)
                
                Text(cmd)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
            } else {
                Text("Terminal Output")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.foreground)
            }
            
            Spacer()
            
            exitCodeBadge
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.ansiMuted)
            }
            .buttonStyle(.plain)
            
            if let cmd = command, !cmd.isEmpty {
                Button {
                    Clipboard.copy(cmd)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.ansiMuted)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .help("Copy command")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.headerBackground)
    }
    
    private var exitCodeBadge: some View {
        HStack(spacing: 4) {
            switch resolvedExitCode {
            case .running:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 9, weight: .semibold))
            }
            
            if let label = resolvedExitCode.label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundStyle(exitCodeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(exitCodeColor.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private var outputView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if trimmedOutput.isEmpty {
                Text(isRunning ? "Waiting for output..." : "No output")
                    .font(.custom(terminalFontName, size: fontSize))
                    .foregroundStyle(theme.ansiMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(ANSIParser.parse(trimmedOutput))
                    .font(.custom(terminalFontName, size: fontSize))
                    .foregroundStyle(theme.foreground)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: 150)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.background)
    }

    private func startLoading() {
        loadTask?.cancel()

        loadTask = Task { [weak agentSession] in
            guard let session = agentSession else { return }

            var exitedIterations = 0
            let gracePeriodIterations = TerminalOutputDefaults.gracePeriodIterations

            for _ in 0..<TerminalOutputDefaults.maxPollIterationsInline {
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

                if !running {
                    exitedIterations += 1
                    if exitedIterations >= gracePeriodIterations || !terminalOutput.isEmpty {
                        break
                    }
                }

                try? await Task.sleep(nanoseconds: TerminalOutputDefaults.pollIntervalNanoseconds)
            }
        }
    }
}
