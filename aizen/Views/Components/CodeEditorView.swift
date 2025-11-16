//
//  CodeEditorView.swift
//  aizen
//
//  Code editor with line numbers and syntax highlighting using CodeEditSourceEditor
//

import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

struct CodeEditorView: View {
    let content: String
    let language: String?
    var isEditable: Bool = false
    var onContentChange: ((String) -> Void)?

    @State private var text: String
    @State private var editorState = SourceEditorState()

    // Editor settings from AppStorage
    @AppStorage("editorTheme") private var editorTheme: String = "Catppuccin Mocha"
    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 12.0
    @AppStorage("editorWrapLines") private var editorWrapLines: Bool = true
    @AppStorage("editorShowMinimap") private var editorShowMinimap: Bool = false
    @AppStorage("editorShowGutter") private var editorShowGutter: Bool = true
    @AppStorage("editorIndentSpaces") private var editorIndentSpaces: Int = 4

    init(content: String, language: String?, isEditable: Bool = false, onContentChange: ((String) -> Void)? = nil) {
        self.content = content
        self.language = language
        self.isEditable = isEditable
        self.onContentChange = onContentChange
        _text = State(initialValue: content)
    }

    var body: some View {
        let theme = GhosttyThemeParser.loadTheme(named: editorTheme) ?? defaultTheme()

        SourceEditor(
            $text,
            language: detectedLanguage,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: theme,
                    font: NSFont(name: editorFontFamily, size: editorFontSize) ?? .monospacedSystemFont(ofSize: editorFontSize, weight: .regular),
                    wrapLines: editorWrapLines
                ),
                behavior: .init(
                    indentOption: .spaces(count: editorIndentSpaces)
                ),
                peripherals: .init(
                    showGutter: editorShowGutter,
                    showMinimap: editorShowMinimap
                )
            ),
            state: $editorState
        )
        .disabled(!isEditable)
        .clipped()
        .onChange(of: content) { newValue in
            if text != newValue {
                text = newValue
            }
        }
        .onChange(of: text) { newValue in
            if isEditable {
                onContentChange?(newValue)
            }
        }
    }

    private func defaultTheme() -> EditorTheme {
        let bg = NSColor(named: "EditorBackground") ?? NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        let fg = NSColor(named: "EditorText") ?? NSColor(red: 0.8, green: 0.84, blue: 0.96, alpha: 1.0)

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
            variables: .init(color: .systemBlue),
            values: .init(color: .systemOrange),
            numbers: .init(color: .systemOrange),
            strings: .init(color: .systemGreen),
            characters: .init(color: .systemGreen),
            comments: .init(color: .systemGray)
        )
    }

    private var detectedLanguage: CodeLanguage {
        guard let lang = language?.lowercased() else {
            return .default
        }

        switch lang {
        case "swift": return .swift
        case "javascript", "js", "jsx": return .javascript
        case "typescript", "ts", "tsx": return .tsx
        case "python", "py": return .python
        case "ruby", "rb": return .ruby
        case "java": return .java
        case "c": return .c
        case "cpp", "c++": return .cpp
        case "go": return .go
        case "rust", "rs": return .rust
        case "php": return .php
        case "html": return .html
        case "css": return .css
        case "json": return .json
        case "markdown", "md": return .markdown
        case "bash", "sh": return .bash
        default: return .default
        }
    }
}
