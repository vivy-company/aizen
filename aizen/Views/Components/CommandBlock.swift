//
//  CommandBlock.swift
//  aizen
//
//  Shell command display with prompt styling, exit code badge, and expandable output
//

import SwiftUI

// MARK: - Exit Code

enum ExitCodeStatus {
    case success
    case failure(code: Int)
    case running
    case unknown
    
    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .running: return .blue
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
    
    var label: String {
        switch self {
        case .success: return "0"
        case .failure(let code): return "\(code)"
        case .running: return "..."
        case .unknown: return "?"
        }
    }
}

// MARK: - Command Block View

struct CommandBlock: View {
    let command: String
    let output: String?
    let exitCode: ExitCodeStatus
    var workingDirectory: String?
    var isStreaming: Bool = false
    
    @State private var isExpanded = true
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
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
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96)
    }
    
    private var headerBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.94)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
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
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                .fill(exitCode.color)
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
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            
            Text("$")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
            
            Text(command)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .textSelection(.enabled)
            
            Spacer()
            
            if let dir = workingDirectory {
                Text(shortenPath(dir))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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
        .background(headerBackground)
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
            
            Text(exitCode.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(exitCode.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(exitCode.color.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private var outputView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(trimmedOutput)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
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
                workingDirectory: "/Users/dev/my-project"
            )
            
            CommandBlock(
                command: "cargo build --release",
                output: nil,
                exitCode: .running,
                workingDirectory: "/Users/dev/rust-app"
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
                workingDirectory: "/Users/dev/python-project"
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
                exitCode: .success
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
