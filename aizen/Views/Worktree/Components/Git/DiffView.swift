//
//  DiffView.swift
//  aizen
//
//  Unified inline diff viewer for git changes
//

import SwiftUI

struct DiffView: View {
    let fileName: String
    let filePath: String
    let repoPath: String
    let onClose: () -> Void

    @State private var diffLines: [DiffLine] = []
    @State private var isLoading: Bool = true
    @State private var error: String?

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 12.0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                FileIconView(path: filePath, size: 13)
                Text(fileName)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(height: 33)

            Divider()

            // Content
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading diff...")
                        .foregroundColor(.secondary)
                        .padding(.top)
                    Spacer()
                }
            } else if let error = error {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .padding(.top)
                    Spacer()
                }
            } else if diffLines.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No changes to display")
                        .foregroundColor(.secondary)
                        .padding(.top)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffLines) { line in
                            DiffLineView(
                                line: line,
                                fontSize: editorFontSize,
                                fontFamily: editorFontFamily
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: filePath) {
            await loadDiff()
        }
    }

    private func loadDiff() async {
        isLoading = true
        error = nil

        do {
            let executor = GitCommandExecutor()

            // Try diff against HEAD first, fall back to plain diff for new repos without commits
            var diffOutput: String
            do {
                diffOutput = try await executor.executeGit(
                    arguments: ["diff", "HEAD", "--", filePath],
                    at: repoPath
                )
            } catch {
                // HEAD doesn't exist (new repo), try diff without HEAD
                diffOutput = try await executor.executeGit(
                    arguments: ["diff", "--", filePath],
                    at: repoPath
                )
            }

            diffLines = parseUnifiedDiff(diffOutput)
            isLoading = false
        } catch {
            self.error = "Failed to load diff: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

// MARK: - Diff Line Model

struct DiffLine: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let oldLineNumber: String?
    let newLineNumber: String?
    let content: String
    let type: DiffLineType
}

enum DiffLineType {
    case added
    case deleted
    case context
    case header
}

// MARK: - Diff Line View

struct DiffLineView: View {
    let line: DiffLine
    let fontSize: Double
    let fontFamily: String

    var body: some View {
        HStack(spacing: 0) {
            // Line numbers
            HStack(spacing: 4) {
                Text(line.oldLineNumber ?? "")
                    .frame(width: 40, alignment: .trailing)
                    .foregroundColor(.secondary)
                    .opacity(line.oldLineNumber != nil ? 0.7 : 0)

                Text(line.newLineNumber ?? "")
                    .frame(width: 40, alignment: .trailing)
                    .foregroundColor(.secondary)
                    .opacity(line.newLineNumber != nil ? 0.7 : 0)
            }
            .font(.custom(fontFamily, size: fontSize - 1))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Diff marker
            Text(diffMarker)
                .frame(width: 20, alignment: .center)
                .font(.custom(fontFamily, size: fontSize))
                .foregroundColor(markerColor)
                .padding(.vertical, 2)

            // Line content
            Text(line.content.isEmpty ? " " : line.content)
                .font(.custom(fontFamily, size: fontSize))
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .padding(.vertical, 2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backgroundColor)
    }

    private var diffMarker: String {
        switch line.type {
        case .added: return "+"
        case .deleted: return "-"
        case .context: return " "
        case .header: return ""
        }
    }

    private var markerColor: Color {
        switch line.type {
        case .added: return .green
        case .deleted: return .red
        case .context: return .clear
        case .header: return .secondary
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return Color.green.opacity(0.2)
        case .deleted: return Color.red.opacity(0.2)
        case .context: return Color.clear
        case .header: return Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }
}

// MARK: - Diff Parsing

func parseUnifiedDiff(_ diffOutput: String) -> [DiffLine] {
    var lines: [DiffLine] = []
    var lineCounter = 0
    var oldLineNum = 0
    var newLineNum = 0

    let diffLines = diffOutput.components(separatedBy: .newlines)

    for line in diffLines {
        if line.hasPrefix("@@") {
            // Hunk header
            let components = line.components(separatedBy: " ")
            for component in components {
                if component.hasPrefix("-") && !component.hasPrefix("---") {
                    let rangeStr = String(component.dropFirst())
                    if let num = rangeStr.components(separatedBy: ",").first, let start = Int(num) {
                        oldLineNum = start - 1
                    }
                } else if component.hasPrefix("+") && !component.hasPrefix("+++") {
                    let rangeStr = String(component.dropFirst())
                    if let num = rangeStr.components(separatedBy: ",").first, let start = Int(num) {
                        newLineNum = start - 1
                    }
                }
            }

            lines.append(DiffLine(
                lineNumber: lineCounter,
                oldLineNumber: nil,
                newLineNumber: nil,
                content: line,
                type: .header
            ))
            lineCounter += 1
        } else if line.hasPrefix("+++") || line.hasPrefix("---") ||
                  line.hasPrefix("diff ") || line.hasPrefix("index ") {
            // Skip file headers
            continue
        } else if line.hasPrefix("+") {
            // Added line
            newLineNum += 1
            lines.append(DiffLine(
                lineNumber: lineCounter,
                oldLineNumber: nil,
                newLineNumber: String(newLineNum),
                content: String(line.dropFirst()),
                type: .added
            ))
            lineCounter += 1
        } else if line.hasPrefix("-") {
            // Deleted line
            oldLineNum += 1
            lines.append(DiffLine(
                lineNumber: lineCounter,
                oldLineNumber: String(oldLineNum),
                newLineNumber: nil,
                content: String(line.dropFirst()),
                type: .deleted
            ))
            lineCounter += 1
        } else if line.hasPrefix(" ") {
            // Context line
            oldLineNum += 1
            newLineNum += 1
            lines.append(DiffLine(
                lineNumber: lineCounter,
                oldLineNumber: String(oldLineNum),
                newLineNumber: String(newLineNum),
                content: String(line.dropFirst()),
                type: .context
            ))
            lineCounter += 1
        }
    }

    return lines
}
