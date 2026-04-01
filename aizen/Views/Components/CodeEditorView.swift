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

    @State private var document: VVDocument
    @State private var gitDiffText: String?

    // Editor settings from AppStorage
    @AppStorage(AppearanceSettings.codeFontFamilyKey) private var editorFontFamily: String = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.codeFontSizeKey) private var editorFontSize: Double = AppearanceSettings.defaultCodeFontSize
    @AppStorage("editorWrapLines") private var editorWrapLines: Bool = true
    @AppStorage("editorShowGutter") private var editorShowGutter: Bool = true
    @AppStorage("editorIndentSpaces") private var editorIndentSpaces: Int = 4
    @Environment(\.colorScheme) private var colorScheme

    private struct DocumentSyncKey: Hashable {
        let content: String
        let language: String?
    }

    private struct DiffReloadKey: Hashable {
        let content: String
        let filePath: String?
        let repoPath: String?
        let hasUnsavedChanges: Bool
    }

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

    private var documentSyncKey: DocumentSyncKey {
        DocumentSyncKey(content: content, language: language)
    }

    private var diffReloadKey: DiffReloadKey {
        DiffReloadKey(
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
        onContentChange: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.language = language
        self.isEditable = isEditable
        self.filePath = filePath
        self.repoPath = repoPath
        self.hasUnsavedChanges = hasUnsavedChanges
        self.onContentChange = onContentChange

        let document = VVDocument(text: content, language: VVLanguageBridge.language(from: language))
        _document = State(initialValue: document)
    }

    var body: some View {
        VVCodeView(document: $document)
            .language(detectedLanguage)
            .theme(editorThemeValue)
            .configuration(editorConfiguration)
            .gitDiff(gitDiffText)
            .lspDisabled(true)
            .onTextChange { newValue in
                if isEditable, newValue != content {
                    onContentChange?(newValue)
                }
            }
            .disabled(!isEditable)
            .clipped()
            .task(id: documentSyncKey) {
                syncDocument()
            }
            .task(id: diffReloadKey) {
                await reloadGitDiffIfNeeded()
            }
    }

    private func syncDocument() {
        if document.text != content {
            document.text = content
        }

        let resolvedLanguage = VVLanguageBridge.language(from: language)
        if document.language != resolvedLanguage {
            document.language = resolvedLanguage
        }
    }

    private func reloadGitDiffIfNeeded() async {
        guard !hasUnsavedChanges else { return }

        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        await loadGitDiff()
    }

    private func loadGitDiff() async {
        guard let filePath,
              let repoPath else {
            await MainActor.run { gitDiffText = nil }
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let repoURL = URL(fileURLWithPath: repoPath)
        var relativePath = fileURL.path
        if fileURL.path.hasPrefix(repoURL.path + "/") {
            relativePath = String(fileURL.path.dropFirst(repoURL.path.count + 1))
        }

        if let diff = await runGitDiff(repoPath: repoPath, arguments: ["diff", "HEAD", "--", relativePath]),
           !diff.isEmpty {
            await MainActor.run { gitDiffText = diff }
            return
        }

        if let diff = await runGitDiff(repoPath: repoPath, arguments: ["diff", "--", relativePath]),
           !diff.isEmpty {
            await MainActor.run { gitDiffText = diff }
            return
        }

        await MainActor.run { gitDiffText = nil }
    }

    private func runGitDiff(repoPath: String, arguments: [String]) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "-C", repoPath] + arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                return nil
            }

            process.waitUntilExit()

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
    }

}
