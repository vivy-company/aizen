//
//  CodeBlockView.swift
//  aizen
//
//  Code block rendering with syntax highlighting
//

import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

struct CodeBlockView: View {
    let code: String
    let language: String?
    var isStreaming: Bool = false

    /// Trimmed code with empty lines removed from start and end
    private var trimmedCode: String {
        // Split into lines, find first and last non-empty lines
        let lines = code.components(separatedBy: "\n")
        var startIndex = 0
        var endIndex = lines.count - 1

        // Find first non-empty line
        while startIndex < lines.count && lines[startIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            startIndex += 1
        }

        // Find last non-empty line
        while endIndex >= startIndex && lines[endIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            endIndex -= 1
        }

        guard startIndex <= endIndex else { return "" }
        return lines[startIndex...endIndex].joined(separator: "\n")
    }

    @State private var showCopyConfirmation = false
    @State private var highlightedText: AttributedString?
    @State private var isHovering = false
    @AppStorage("editorTheme") private var editorTheme: String = "Catppuccin Mocha"
    @AppStorage("editorThemeLight") private var editorThemeLight: String = "Catppuccin Latte"
    @AppStorage("editorUsePerAppearanceTheme") private var usePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return editorTheme }
        return colorScheme == .dark ? editorTheme : editorThemeLight
    }

    private var headerBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.15)
            : Color(white: 0.95)
    }

    private var codeBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.1)
            : Color(white: 0.98)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
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

                // Line count
                let lineCount = trimmedCode.components(separatedBy: "\n").count
                Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                // Copy button
                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        if isHovering {
                            Text(showCopyConfirmation ? "Copied" : "Copy")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundStyle(showCopyConfirmation ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(isHovering ? 0.15 : 0))
                    )
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)

            // Code content
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(1...max(1, trimmedCode.components(separatedBy: "\n").count), id: \.self) { num in
                            Text("\(num)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(height: 18)
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.leading, 8)

                    Divider()
                        .frame(height: CGFloat(max(1, trimmedCode.components(separatedBy: "\n").count)) * 18)

                    // Code
                    Group {
                        if let highlighted = highlightedText {
                            Text(highlighted)
                        } else {
                            Text(trimmedCode)
                                .foregroundColor(.primary)
                        }
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.leading, 12)
                }
                .padding(.vertical, 10)
            }
            .background(codeBackground)
            .task(id: highlightTaskKey) {
                guard !isStreaming else { return }
                let snapshot = trimmedCode
                await performHighlight(codeSnapshot: snapshot)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedCode, forType: .string)

        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private var highlightTaskKey: String {
        "\(trimmedCode.hashValue)-\(language ?? "none")-\(effectiveThemeName)-\(isStreaming ? "stream" : "final")"
    }

    private func performHighlight(codeSnapshot: String) async {
        let detectedLanguage: CodeLanguage
        if let lang = language, !lang.isEmpty {
            detectedLanguage = LanguageDetection.languageFromFence(lang)
        } else {
            detectedLanguage = .default
        }

        // Load theme
        let theme = GhosttyThemeParser.loadTheme(named: effectiveThemeName) ?? defaultTheme()

        // Use shared highlighting queue (limits concurrent highlighting, provides caching)
        if let attributed = await HighlightingQueue.shared.highlight(
            code: codeSnapshot,
            language: detectedLanguage,
            theme: theme
        ) {
            if codeSnapshot == trimmedCode {
                highlightedText = attributed
            }
        } else {
            // Fallback to plain text on error or cancellation
            if highlightedText == nil, codeSnapshot == trimmedCode {
                highlightedText = AttributedString(codeSnapshot)
            }
        }
    }

    private func defaultTheme() -> EditorTheme {
        let bg = NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        let fg = NSColor(red: 0.8, green: 0.84, blue: 0.96, alpha: 1.0)

        return EditorTheme(
            text: .init(color: fg),
            insertionPoint: fg,
            invisibles: .init(color: .systemGray),
            background: bg,
            lineHighlight: bg.withAlphaComponent(0.05),
            selection: .selectedTextBackgroundColor,
            keywords: .init(color: .systemPurple),
            commands: .init(color: .systemBlue),
            types: .init(color: .systemYellow),
            attributes: .init(color: .systemRed),
            variables: .init(color: .systemCyan),
            values: .init(color: .systemOrange),
            numbers: .init(color: .systemOrange),
            strings: .init(color: .systemGreen),
            characters: .init(color: .systemGreen),
            comments: .init(color: .systemGray)
        )
    }
}
