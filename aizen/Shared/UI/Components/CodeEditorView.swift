//
//  CodeEditorView.swift
//  aizen
//
//  Code editor with line numbers and syntax highlighting using VVCode
//

import AppKit
import SwiftUI
import VVCode

struct CodeEditorView: View {
    let content: String
    let language: String?
    var isEditable: Bool = false
    var filePath: String? = nil
    var repoPath: String? = nil
    var hasUnsavedChanges: Bool = false
    var onContentChange: ((String) -> Void)?

    @StateObject private var runtime: CodeEditorRuntime

    // Editor settings from AppStorage
    @AppStorage(AppearanceSettings.codeFontFamilyKey) private var editorFontFamily: String = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.codeFontSizeKey) private var editorFontSize: Double = AppearanceSettings.defaultCodeFontSize
    @AppStorage("editorWrapLines") private var editorWrapLines: Bool = true
    @AppStorage("editorShowGutter") private var editorShowGutter: Bool = true
    @AppStorage("editorIndentSpaces") private var editorIndentSpaces: Int = 4
    @Environment(\.colorScheme) private var colorScheme

    private var detectedLanguage: VVLanguage? {
        VVLanguageBridge.language(from: language)
    }

    private var editorThemeValue: VVTheme {
        AppearanceSettings.resolvedTheme(colorScheme: colorScheme)
    }

    private var editorConfiguration: VVConfiguration {
        let font = AppearanceSettings.resolvedNSFont(
            family: editorFontFamily,
            size: editorFontSize,
            monospacedFallback: true,
            requireFixedPitch: true
        )

        return VVConfiguration.default
            .with(font: font)
            .with(tabWidth: editorIndentSpaces)
            .with(wrapLines: editorWrapLines)
            .with(showLineNumbers: editorShowGutter)
            .with(showGutter: editorShowGutter)
            .with(showGitGutter: editorShowGutter)
    }

    private var documentSyncKey: CodeEditorRuntime.DocumentSyncKey {
        CodeEditorRuntime.DocumentSyncKey(content: content, language: language)
    }

    private var diffReloadKey: CodeEditorRuntime.DiffReloadKey {
        CodeEditorRuntime.DiffReloadKey(
            content: content,
            filePath: filePath,
            repoPath: repoPath,
            hasUnsavedChanges: hasUnsavedChanges
        )
    }

    init(
        content: String,
        language: String?,
        isEditable: Bool = false,
        filePath: String? = nil,
        repoPath: String? = nil,
        hasUnsavedChanges: Bool = false,
        runtime: CodeEditorRuntime? = nil,
        onContentChange: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.language = language
        self.isEditable = isEditable
        self.filePath = filePath
        self.repoPath = repoPath
        self.hasUnsavedChanges = hasUnsavedChanges
        self.onContentChange = onContentChange
        _runtime = StateObject(
            wrappedValue: runtime ?? CodeEditorRuntime(content: content, language: language)
        )
    }

    var body: some View {
        VVCodeView(document: documentBinding)
            .language(detectedLanguage)
            .theme(editorThemeValue)
            .configuration(editorConfiguration)
            .gitDiff(runtime.gitDiffText)
            .lspDisabled(true)
            .onTextChange { newValue in
                if isEditable, newValue != content {
                    onContentChange?(newValue)
                }
            }
            .disabled(!isEditable)
            .clipped()
            .task(id: documentSyncKey) {
                runtime.syncDocument(content: content, language: language)
            }
            .task(id: diffReloadKey) {
                runtime.reloadGitDiffIfNeeded(
                    content: content,
                    filePath: filePath,
                    repoPath: repoPath,
                    hasUnsavedChanges: hasUnsavedChanges
                )
            }
    }

    private var documentBinding: Binding<VVDocument> {
        Binding(
            get: { runtime.document },
            set: { runtime.document = $0 }
        )
    }
}
