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

    @State private var highlightedText: AttributedString?
    @State private var highlightedPreview: AttributedString?
    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var didSetInitialExpand = false
    @AppStorage("editorTheme") private var editorTheme: String = "Aizen Dark"
    @AppStorage("editorThemeLight") private var editorThemeLight: String = "Aizen Light"
    @AppStorage("editorUsePerAppearanceTheme") private var usePerAppearanceTheme = false
    @AppStorage(ChatSettings.codeBlockExpansionModeKey) private var codeBlockExpansionMode = ChatSettings.defaultCodeBlockExpansionMode
    @AppStorage(ChatSettings.enableAnimationsKey) private var enableAnimations = ChatSettings.defaultEnableAnimations
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return editorTheme }
        return colorScheme == .dark ? editorTheme : editorThemeLight
    }

    private var headerBackground: Color {
        CodeBlockColors.headerBackground()
    }

    private var codeBackground: Color {
        CodeBlockColors.contentBackground()
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

    private var shouldHighlight: Bool {
        guard !isStreaming else { return false }
        let codeToCheck = isExpanded ? trimmedCode : previewText
        if codeToCheck.count > 4000 { return false }
        return true
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
                Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                CopyHoverButton(
                    helpText: "Copy code",
                    isHovered: isHovering,
                    action: copyCode
                )

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)

            Group {
                if isExpanded {
                    codeContent(text: trimmedCode, displayLineCount: lineCount, highlighted: highlightedText)
                } else {
                    codeContent(text: previewText, displayLineCount: previewLineCount, highlighted: highlightedPreview)
                }
            }
            .task(id: highlightTaskKey) {
                guard shouldHighlight else {
                    if highlightedText != nil { highlightedText = nil }
                    if highlightedPreview != nil { highlightedPreview = nil }
                    return
                }
                await performHighlight(codeSnapshot: trimmedCode, isPreview: false)
                await performHighlight(codeSnapshot: previewText, isPreview: true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 4, x: 0, y: 2)
        .onHover { hovering in
            if enableAnimations {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            } else {
                isHovering = hovering
            }
        }
        .task(id: trimmedCode.hashValue) {
            guard !didSetInitialExpand else { return }
            let mode = CodeBlockExpansionMode(rawValue: codeBlockExpansionMode) ?? .auto
            switch mode {
            case .auto: isExpanded = lineCount <= 12
            case .expanded: isExpanded = true
            case .collapsed: isExpanded = false
            }
            didSetInitialExpand = true
        }
    }

    private func copyCode() {
        Clipboard.copy(trimmedCode)
    }

    private var highlightTaskKey: String {
        "\(trimmedCode.hashValue)-\(language ?? "none")-\(effectiveThemeName)-\(isStreaming ? "stream" : "final")-\(isExpanded ? "expanded" : "collapsed")"
    }

    private func performHighlight(codeSnapshot: String, isPreview: Bool) async {
        let detectedLanguage: CodeLanguage
        if let lang = language, !lang.isEmpty {
            detectedLanguage = LanguageDetection.languageFromFence(lang)
        } else {
            detectedLanguage = .default
        }

        let theme = GhosttyThemeParser.loadTheme(named: effectiveThemeName) ?? defaultTheme()

        if let attributed = await HighlightingQueue.shared.highlight(
            code: codeSnapshot,
            language: detectedLanguage,
            theme: theme
        ) {
            if isPreview {
                if codeSnapshot == previewText {
                    highlightedPreview = attributed
                }
            } else {
                if codeSnapshot == trimmedCode {
                    highlightedText = attributed
                }
            }
        }
    }

    private func toggleExpanded() {
        if enableAnimations {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } else {
            isExpanded.toggle()
        }
    }

    @ViewBuilder
    private func codeContent(text: String, displayLineCount: Int, highlighted: AttributedString?) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...displayLineCount, id: \.self) { num in
                        Text("\(num)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(height: 18)
                    }
                }
                .padding(.trailing, 12)
                .padding(.leading, 8)

                Divider()
                    .frame(height: CGFloat(displayLineCount) * 18)

                Group {
                    if let highlighted = highlighted {
                        Text(highlighted)
                    } else {
                        Text(text)
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
