//
//  CodeBlockView.swift
//  aizen
//
//  Code block rendering backed by VVCode.
//

import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?
    var isStreaming: Bool = false

    @State private var isExpanded = false
    @State private var didSetInitialExpand = false

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 12.0
    @Environment(\.colorScheme) private var colorScheme

    /// Trimmed code with empty lines removed from start and end
    private var trimmedCode: String {
        let lines = code.components(separatedBy: "\n")
        var startIndex = 0
        var endIndex = lines.count - 1

        while startIndex < lines.count && lines[startIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            startIndex += 1
        }

        while endIndex >= startIndex && lines[endIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            endIndex -= 1
        }

        guard startIndex <= endIndex else { return "" }
        return lines[startIndex...endIndex].joined(separator: "\n")
    }

    private var headerBackground: Color {
        CodeBlockColors.headerBackground(for: colorScheme)
    }

    private var codeBackground: Color {
        CodeBlockColors.contentBackground(for: colorScheme)
    }

    private var lineCount: Int {
        max(1, trimmedCode.components(separatedBy: "\n").count)
    }

    private var previewText: String {
        let lines = trimmedCode.components(separatedBy: "\n")
        let previewCount = min(8, lines.count)
        return lines.prefix(previewCount).joined(separator: "\n")
    }

    private var previewLineCount: Int {
        max(1, previewText.components(separatedBy: "\n").count)
    }

    private var shouldTruncate: Bool {
        lineCount > 8
    }

    private var languageIcon: String {
        guard let lang = language?.lowercased() else { return "chevron.left.forwardslash.chevron.right" }
        switch lang {
        case "swift": return "swift"
        case "python", "py": return "text.page"
        case "javascript", "js", "typescript", "ts": return "curlybraces"
        case "rust", "rs": return "gearshape.2"
        case "go", "golang": return "arrow.right.circle"
        case "ruby", "rb": return "diamond"
        case "java", "kotlin": return "cup.and.saucer"
        case "c", "cpp", "c++", "h", "hpp": return "cpu"
        case "html", "xml": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass": return "paintbrush"
        case "json", "yaml", "yml", "toml": return "doc.text"
        case "sql": return "cylinder"
        case "shell", "bash", "zsh", "sh": return "terminal"
        case "markdown", "md": return "text.alignleft"
        case "dockerfile", "docker": return "shippingbox"
        default: return "doc.plaintext"
        }
    }

    private var previewHeight: CGFloat {
        let lineHeight = max(16, CGFloat(editorFontSize + 5))
        return CGFloat(previewLineCount) * lineHeight + 18
    }

    private var expandedHeight: CGFloat {
        let lineHeight = max(16, CGFloat(editorFontSize + 5))
        let preferred = CGFloat(lineCount) * lineHeight + 24
        return min(max(preferred, 120), 520)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: languageIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                CopyHoverButton(
                    helpText: "Copy code",
                    isHovered: false,
                    action: copyCode
                )

                if shouldTruncate {
                    Button(action: toggleExpanded) {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isExpanded ? "Collapse" : "Expand")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)

            Group {
                if isStreaming {
                    MonospaceTextPanel(
                        text: previewText,
                        maxHeight: 160,
                        font: .system(size: 13, design: .monospaced),
                        backgroundColor: codeBackground,
                        padding: 10
                    )
                } else {
                    VVCodeSnippetView(
                        text: isExpanded ? trimmedCode : previewText,
                        languageHint: language,
                        maxHeight: isExpanded ? expandedHeight : previewHeight,
                        showLineNumbers: true,
                        wrapLines: false,
                        fontFamily: editorFontFamily,
                        fontSize: editorFontSize
                    )
                }
            }
            .background(codeBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 4, x: 0, y: 2)
        .task(id: trimmedCode.hashValue) {
            guard !didSetInitialExpand else { return }
            isExpanded = lineCount <= 12
            didSetInitialExpand = true
        }
    }

    private func copyCode() {
        Clipboard.copy(trimmedCode)
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isExpanded.toggle()
        }
    }
}
