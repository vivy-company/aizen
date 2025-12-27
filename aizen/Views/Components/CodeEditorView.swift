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
    var filePath: String? = nil
    var repoPath: String? = nil
    var onContentChange: ((String) -> Void)?

    @State private var text: String
    @State private var editorState = SourceEditorState()
    @State private var gitDiffStatus: [Int: GitDiffLineStatus] = [:]
    @State private var gitDiffCoordinator = GitDiffCoordinator()

    // Editor settings from AppStorage
    @AppStorage("editorTheme") private var editorTheme: String = "Aizen Dark"
    @AppStorage("editorThemeLight") private var editorThemeLight: String = "Aizen Light"
    @AppStorage("editorUsePerAppearanceTheme") private var usePerAppearanceTheme = false
    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 12.0
    @AppStorage("editorWrapLines") private var editorWrapLines: Bool = true
    @AppStorage("editorShowMinimap") private var editorShowMinimap: Bool = false
    @AppStorage("editorShowGutter") private var editorShowGutter: Bool = true
    @AppStorage("editorIndentSpaces") private var editorIndentSpaces: Int = 4
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return editorTheme }
        return colorScheme == .dark ? editorTheme : editorThemeLight
    }

    init(
        content: String,
        language: String?,
        isEditable: Bool = false,
        filePath: String? = nil,
        repoPath: String? = nil,
        onContentChange: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.language = language
        self.isEditable = isEditable
        self.filePath = filePath
        self.repoPath = repoPath
        self.onContentChange = onContentChange
        _text = State(initialValue: content)
    }

    var body: some View {
        let theme = GhosttyThemeParser.loadTheme(named: effectiveThemeName) ?? defaultTheme()

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
            state: $editorState,
            coordinators: [gitDiffCoordinator]
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
        .task {
            // Load git diff status when view appears
            await loadGitDiff()
        }
        .onChange(of: content) { _ in
            // Reload git diff when content changes
            Task {
                await loadGitDiff()
            }
        }
    }

    private func loadGitDiff() async {
        guard let filePath = filePath,
              let repoPath = repoPath else {
            return
        }

        do {
            let provider = GitDiffProvider()
            let diffStatus = try await provider.getLineDiff(filePath: filePath, repoPath: repoPath)
            await MainActor.run {
                gitDiffStatus = diffStatus
                gitDiffCoordinator.gitDiffStatus = diffStatus
            }
        } catch {
            // Silently fail if git diff isn't available
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
            return CodeLanguage.default
        }

        // Use LanguageDetection to map extension to language
        return LanguageDetection.codeLanguageFromString(lang)
    }
}
