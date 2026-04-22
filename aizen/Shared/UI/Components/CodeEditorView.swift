//
//  CodeEditorView.swift
//  aizen
//
//  Code editor with line numbers and syntax highlighting using VVCode
//

import AppKit
import SwiftUI
import VVCode
import VVGit

struct CodeEditorView: View {
    let content: String
    let language: String?
    var isEditable: Bool = false
    var filePath: String? = nil
    var repoPath: String? = nil
    var hasUnsavedChanges: Bool = false
    var selectionRequest: SearchOpenRequest? = nil
    var shouldFocusOnAppear: Bool = true
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

    private struct SelectionSyncKey: Hashable {
        let filePath: String?
        let selectionRequest: SearchOpenRequest?
    }

    private var selectionSyncKey: SelectionSyncKey {
        SelectionSyncKey(filePath: filePath, selectionRequest: selectionRequest)
    }

    init(
        content: String,
        language: String?,
        isEditable: Bool = false,
        filePath: String? = nil,
        repoPath: String? = nil,
        hasUnsavedChanges: Bool = false,
        selectionRequest: SearchOpenRequest? = nil,
        shouldFocusOnAppear: Bool = true,
        runtime: CodeEditorRuntime? = nil,
        onContentChange: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.language = language
        self.isEditable = isEditable
        self.filePath = filePath
        self.repoPath = repoPath
        self.hasUnsavedChanges = hasUnsavedChanges
        self.selectionRequest = selectionRequest
        self.shouldFocusOnAppear = shouldFocusOnAppear
        self.onContentChange = onContentChange
        _runtime = StateObject(
            wrappedValue: runtime ?? CodeEditorRuntime(content: content, language: language)
        )
    }

    var body: some View {
        AizenCodeEditorRepresentable(
            document: documentBinding,
            runtime: runtime,
            language: detectedLanguage,
            theme: editorThemeValue,
            configuration: editorConfiguration,
            gitDiff: runtime.gitDiffText,
            filePath: filePath,
            shouldFocusOnAppear: shouldFocusOnAppear,
            onTextChange: { newValue in
                if isEditable, newValue != content {
                    onContentChange?(newValue)
                }
            }
        )
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
            .task(id: selectionSyncKey) {
                guard let selectionRequest else { return }
                runtime.queueSelectionRequest(selectionRequest)
            }
    }

    private var documentBinding: Binding<VVDocument> {
        Binding(
            get: { runtime.document },
            set: { runtime.document = $0 }
        )
    }
}

private struct AizenCodeEditorRepresentable: NSViewRepresentable {
    @Binding var document: VVDocument
    let runtime: CodeEditorRuntime
    let language: VVLanguage?
    let theme: VVTheme
    let configuration: VVConfiguration
    let gitDiff: String?
    let filePath: String?
    let shouldFocusOnAppear: Bool
    let onTextChange: ((String) -> Void)?

    func makeNSView(context: Context) -> VVMetalEditorContainerView {
        let containerView = VVMetalEditorContainerView(
            frame: .zero,
            configuration: configuration,
            theme: theme
        )

        containerView.delegate = context.coordinator
        containerView.setText(document.text)

        if let language {
            containerView.setLanguage(language)
        }

        if let gitDiff {
            containerView.setGitHunks(VVDiffParser.parse(unifiedDiff: gitDiff))
        }

        if shouldFocusOnAppear {
            DispatchQueue.main.async {
                containerView.focusTextView()
            }
        }

        return containerView
    }

    func updateNSView(_ nsView: VVMetalEditorContainerView, context: Context) {
        if nsView.text != document.text {
            nsView.setText(document.text)
        }

        if let language {
            nsView.setLanguage(language)
        }

        if context.coordinator.lastTheme != theme {
            nsView.setTheme(theme)
            context.coordinator.lastTheme = theme
        }

        if context.coordinator.lastConfiguration != configuration {
            nsView.setConfiguration(configuration)
            context.coordinator.lastConfiguration = configuration
        }

        if context.coordinator.lastGitDiff != gitDiff {
            context.coordinator.lastGitDiff = gitDiff
            let hunks: [VVDiffHunk] = gitDiff.map { VVDiffParser.parse(unifiedDiff: $0) } ?? []
            nsView.setGitHunks(hunks)
        }

        if let range = runtime.consumePendingSelectionRange(for: filePath, content: document.text) {
            nsView.selectRange(range)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: $document, onTextChange: onTextChange)
    }

    final class Coordinator: NSObject, VVEditorDelegate {
        let document: Binding<VVDocument>
        let onTextChange: ((String) -> Void)?
        var lastTheme: VVTheme?
        var lastConfiguration: VVConfiguration?
        var lastGitDiff: String?

        init(document: Binding<VVDocument>, onTextChange: ((String) -> Void)?) {
            self.document = document
            self.onTextChange = onTextChange
        }

        func editorDidChangeText(_ text: String) {
            DispatchQueue.main.async { [weak self] in
                self?.document.wrappedValue.text = text
                self?.onTextChange?(text)
            }
        }

        func editorDidChangeSelection(_ range: NSRange) {}

        func editorDidChangeCursorPosition(_ position: VVTextPosition) {}
    }
}
