//
//  CommandBlock.swift
//  aizen
//

import Combine
import SwiftUI

// MARK: - Exit Code

enum ExitCodeStatus {
    case success
    case failure(code: Int)
    case running
    case unknown
    
    func color(provider: TerminalThemeProvider) -> Color {
        switch self {
        case .success: return provider.ansiGreen
        case .failure: return provider.ansiRed
        case .running: return provider.ansiBlue
        case .unknown: return .secondary
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .running: return "arrow.trianglehead.2.clockwise"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var label: String? {
        switch self {
        case .success: return nil
        case .failure(let code): return "\(code)"
        case .running: return nil
        case .unknown: return nil
        }
    }
}

// MARK: - Terminal Theme Provider

struct TerminalThemeProvider {
    let themeName: String
    
    var background: Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: themeName))
    }
    
    var headerBackground: Color {
        let bg = GhosttyThemeParser.loadBackgroundColor(named: themeName)
        let isLight = bg.luminance > 0.5
        return Color(nsColor: bg.darken(by: isLight ? 0.05 : -0.1))
    }
    
    var foreground: Color {
        ANSIColorProvider.shared.color(for: 7)
    }
    
    var promptColor: Color {
        ANSIColorProvider.shared.color(for: 3)
    }
    
    var ansiRed: Color { ANSIColorProvider.shared.color(for: 1) }
    var ansiGreen: Color { ANSIColorProvider.shared.color(for: 2) }
    var ansiYellow: Color { ANSIColorProvider.shared.color(for: 3) }
    var ansiBlue: Color { ANSIColorProvider.shared.color(for: 4) }
    var ansiMuted: Color { ANSIColorProvider.shared.color(for: 8) }
    
    var borderColor: Color {
        let bg = GhosttyThemeParser.loadBackgroundColor(named: themeName)
        return Color(nsColor: bg.darken(by: bg.luminance > 0.5 ? 0.15 : -0.2))
    }
}

// MARK: - Command Block View

struct CommandBlock: View {
    let command: String
    let output: String?
    let exitCode: ExitCodeStatus
    var workingDirectory: String?
    var isStreaming: Bool = false
    var startTime: Date?
    var endTime: Date?
    
    @State private var isExpanded = true
    @State private var isHovering = false
    @State private var elapsedTime: TimeInterval = 0
    @AppStorage("terminalThemeName") private var themeName = "Aizen Dark"
    @Environment(\.colorScheme) private var colorScheme
    
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var theme: TerminalThemeProvider {
        TerminalThemeProvider(themeName: themeName)
    }
    
    private var hasOutput: Bool {
        guard let output = output else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var trimmedOutput: String {
        output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private var outputLineCount: Int {
        guard hasOutput else { return 0 }
        return trimmedOutput.components(separatedBy: "\n").count
    }
    
    private var exitCodeColor: Color {
        exitCode.color(provider: theme)
    }
    
    private var durationText: String? {
        if let start = startTime {
            let duration: TimeInterval
            if let end = endTime {
                duration = end.timeIntervalSince(start)
            } else if case .running = exitCode {
                duration = elapsedTime
            } else {
                return nil
            }
            return formatDuration(duration)
        }
        return nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let mins = Int(duration) / 60
            let secs = Int(duration) % 60
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(duration) / 3600
            let mins = (Int(duration) % 3600) / 60
            return "\(hours)h \(mins)m"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            if isExpanded && hasOutput {
                Divider()
                    .opacity(0.5)
                
                outputView
            }
        }
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.borderColor, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                .fill(exitCodeColor)
                .frame(width: 3)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08),
            radius: isHovering ? 6 : 3,
            x: 0,
            y: 2
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onReceive(timer) { _ in
            if case .running = exitCode, let start = startTime {
                elapsedTime = Date().timeIntervalSince(start)
            }
        }
        .onAppear {
            if let start = startTime {
                elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.promptColor)
            
            Text("$")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.promptColor)
            
            Text(command)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .textSelection(.enabled)
            
            Spacer()
            
            if let dir = workingDirectory {
                Text(shortenPath(dir))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.ansiMuted)
                    .lineLimit(1)
            }
            
            if let duration = durationText {
                Text(duration)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.ansiMuted)
            }
            
            exitCodeBadge
            
            if hasOutput {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Button {
                Clipboard.copy(command)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Copy command")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.headerBackground)
    }
    
    private var exitCodeBadge: some View {
        HStack(spacing: 4) {
            if case .running = exitCode {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            } else {
                Image(systemName: exitCode.icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            
            if let label = exitCode.label {
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
            Text(ANSIParser.parse(trimmedOutput))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.foreground)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.background)
        .overlay(alignment: .bottomTrailing) {
            if outputLineCount > 10 {
                Text("\(outputLineCount) lines")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isStreaming {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("Streaming...")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(8)
            }
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}

// MARK: - Previews

#Preview("Command Blocks") {
    ScrollView {
        VStack(spacing: 16) {
            CommandBlock(
                command: "npm run build",
                output: """
                > project@1.0.0 build
                > tsc && vite build

                vite v5.0.0 building for production...
                ✓ 142 modules transformed.
                dist/index.html              0.45 kB │ gzip: 0.29 kB
                dist/assets/index-DkEf8s4j.js  142.54 kB │ gzip: 45.21 kB
                ✓ built in 1.24s
                """,
                exitCode: .success,
                workingDirectory: "/Users/dev/my-project",
                startTime: Date().addingTimeInterval(-1.24),
                endTime: Date()
            )
            
            CommandBlock(
                command: "cargo build --release",
                output: nil,
                exitCode: .running,
                workingDirectory: "/Users/dev/rust-app",
                startTime: Date().addingTimeInterval(-45)
            )
            
            CommandBlock(
                command: "python test.py",
                output: """
                Traceback (most recent call last):
                  File "test.py", line 5, in <module>
                    import missing_module
                ModuleNotFoundError: No module named 'missing_module'
                """,
                exitCode: .failure(code: 1),
                workingDirectory: "/Users/dev/python-project",
                startTime: Date().addingTimeInterval(-0.35),
                endTime: Date()
            )
            
            CommandBlock(
                command: "ls -la",
                output: """
                total 48
                drwxr-xr-x  12 user  staff   384 Jan 24 10:30 .
                drwxr-xr-x   5 user  staff   160 Jan 24 09:15 ..
                -rw-r--r--   1 user  staff  1234 Jan 24 10:30 README.md
                -rw-r--r--   1 user  staff   567 Jan 24 10:25 package.json
                drwxr-xr-x   8 user  staff   256 Jan 24 10:30 src
                """,
                exitCode: .success,
                startTime: Date().addingTimeInterval(-0.012),
                endTime: Date()
            )
        }
        .padding()
    }
    .frame(width: 600, height: 700)
}

#Preview("Streaming Command") {
    CommandBlock(
        command: "npm install",
        output: """
        added 1423 packages in 12s

        243 packages are looking for funding
          run `npm fund` for details
        """,
        exitCode: .running,
        isStreaming: true
    )
    .padding()
    .frame(width: 500)
}
