//
//  VVCodeSnippetView.swift
//  aizen
//
//  Lightweight read-only VVCode snippet renderer for chat attachments and blocks.
//

import AppKit
import SwiftUI
import VVCode

struct VVCodeSnippetView: View {
    let text: String
    let languageHint: String?
    var filePath: String? = nil
    var mimeType: String? = nil
    var maxHeight: CGFloat? = nil
    var showLineNumbers: Bool = false
    var wrapLines: Bool = false
    var fontFamily: String? = nil
    var fontSize: Double? = nil

    @State private var document: VVDocument

    @AppStorage(AppearanceSettings.codeFontFamilyKey) private var editorFontFamily: String = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.codeFontSizeKey) private var editorFontSize: Double = AppearanceSettings.defaultCodeFontSize

    @Environment(\.colorScheme) private var colorScheme

    init(
        text: String,
        languageHint: String? = nil,
        filePath: String? = nil,
        mimeType: String? = nil,
        maxHeight: CGFloat? = nil,
        showLineNumbers: Bool = false,
        wrapLines: Bool = false,
        fontFamily: String? = nil,
        fontSize: Double? = nil
    ) {
        self.text = text
        self.languageHint = languageHint
        self.filePath = filePath
        self.mimeType = mimeType
        self.maxHeight = maxHeight
        self.showLineNumbers = showLineNumbers
        self.wrapLines = wrapLines
        self.fontFamily = fontFamily
        self.fontSize = fontSize

        let language = Self.resolveLanguage(languageHint: languageHint, filePath: filePath, mimeType: mimeType)
        _document = State(initialValue: VVDocument(text: text, language: language))
    }

    private var theme: VVTheme {
        AppearanceSettings.resolvedTheme(colorScheme: colorScheme)
    }

    private var resolvedLanguage: VVLanguage? {
        Self.resolveLanguage(languageHint: languageHint, filePath: filePath, mimeType: mimeType)
    }

    private var configuration: VVConfiguration {
        let family = fontFamily ?? editorFontFamily
        let size = fontSize ?? editorFontSize
        let font = AppearanceSettings.resolvedNSFont(
            family: family,
            size: size,
            monospacedFallback: true,
            requireFixedPitch: true
        )

        return VVConfiguration.default
            .with(font: font)
            .with(wrapLines: wrapLines)
            .with(showLineNumbers: showLineNumbers)
            .with(showGutter: showLineNumbers)
            .with(showGitGutter: false)
    }

    var body: some View {
        VVCodeView(document: $document)
            .language(resolvedLanguage)
            .theme(theme)
            .configuration(configuration)
            .lspDisabled(true)
            .disabled(true)
            .frame(maxHeight: maxHeight)
            .onChange(of: text) { _, newValue in
                if document.text != newValue {
                    document.text = newValue
                }
            }
            .onChange(of: languageHint) { _, _ in
                document.language = resolvedLanguage
            }
            .onChange(of: filePath) { _, _ in
                document.language = resolvedLanguage
            }
            .onChange(of: mimeType) { _, _ in
                document.language = resolvedLanguage
            }
    }

    private static func resolveLanguage(
        languageHint: String?,
        filePath: String?,
        mimeType: String?
    ) -> VVLanguage? {
        VVLanguageBridge.language(from: languageHint)
            ?? VVLanguageBridge.language(fromPath: filePath)
            ?? VVLanguageBridge.language(fromMIMEType: mimeType)
    }
}
