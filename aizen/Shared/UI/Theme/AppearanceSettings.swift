//
//  AppearanceSettings.swift
//  aizen
//

import AppKit
import SwiftUI
import VVCode
import VVMarkdown
import VVMetalPrimitives

enum AppearanceSettings {
    static let themeNameKey = "terminalThemeName"
    static let lightThemeNameKey = "terminalThemeNameLight"
    static let usePerAppearanceThemeKey = "terminalUsePerAppearanceTheme"

    static let terminalFontFamilyKey = "terminalFontName"
    static let terminalFontSizeKey = "terminalFontSize"

    static let codeFontFamilyKey = "editorFontFamily"
    static let codeFontSizeKey = "editorFontSize"
    static let diffFontSizeKey = "diffFontSize"
    static let gitDiffRenderStyleKey = "gitDiffRenderStyle"

    static let markdownFontFamilyKey = "chatFontFamily"
    static let markdownFontSizeKey = "chatFontSize"
    static let markdownParagraphSpacingKey = "chatBlockSpacing"
    static let markdownHeadingSpacingKey = "appearanceMarkdownHeadingSpacing"
    static let markdownContentPaddingKey = "appearanceMarkdownContentPadding"

    static let defaultDarkTheme = "Aizen Dark"
    static let defaultLightTheme = "Aizen Light"

    static let defaultTerminalFontFamily = "Menlo"
    static let defaultTerminalFontSize = 12.0

    static let defaultCodeFontFamily = "Menlo"
    static let defaultCodeFontSize = 12.0
    static let defaultDiffFontSize = 11.0
    static let defaultGitDiffRenderStyleRawValue = "inline"

    static let systemFontFamily = "System Font"
    static let defaultMarkdownFontFamily = systemFontFamily
    static let defaultMarkdownFontSize = 14.0
    static let defaultMarkdownParagraphSpacing = 10.0
    static let defaultMarkdownHeadingSpacing = 22.0
    static let defaultMarkdownContentPadding = 0.0

    static let fontSizeRange: ClosedRange<Double> = 8...24
    static let markdownFontSizeRange: ClosedRange<Double> = 12...20
    static let markdownParagraphSpacingRange: ClosedRange<Double> = 4...20
    static let markdownHeadingSpacingRange: ClosedRange<Double> = 12...32
    static let markdownContentPaddingRange: ClosedRange<Double> = 0...24

    static func effectiveThemeName(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        let darkTheme = defaults.string(forKey: themeNameKey) ?? defaultDarkTheme
        guard defaults.bool(forKey: usePerAppearanceThemeKey) else {
            return darkTheme
        }

        let lightTheme = defaults.string(forKey: lightThemeNameKey) ?? defaultLightTheme

        if let colorScheme {
            return colorScheme == .dark ? darkTheme : lightTheme
        }

        let bestMatch = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua ? darkTheme : lightTheme
    }

    static func effectiveThemeName(
        isDarkAppearance: Bool,
        defaults: UserDefaults = .standard
    ) -> String {
        let darkTheme = defaults.string(forKey: themeNameKey) ?? defaultDarkTheme
        guard defaults.bool(forKey: usePerAppearanceThemeKey) else {
            return darkTheme
        }

        let lightTheme = defaults.string(forKey: lightThemeNameKey) ?? defaultLightTheme
        return isDarkAppearance ? darkTheme : lightTheme
    }

    static func effectiveThemeName(
        appearanceMode: String,
        defaults: UserDefaults = .standard
    ) -> String {
        switch appearanceMode {
        case "light":
            return defaults.string(forKey: lightThemeNameKey) ?? defaultLightTheme
        case "dark":
            return defaults.string(forKey: themeNameKey) ?? defaultDarkTheme
        default:
            return effectiveThemeName(defaults: defaults)
        }
    }

    static func resolvedTheme(colorScheme: ColorScheme) -> VVTheme {
        GhosttyThemeParser.loadVVTheme(named: effectiveThemeName(colorScheme: colorScheme))
            ?? (colorScheme == .dark ? .defaultDark : .defaultLight)
    }

    static func resolvedMarkdownTheme(colorScheme: ColorScheme) -> MarkdownTheme {
        let themeName = effectiveThemeName(colorScheme: colorScheme)
        let terminalTheme = GhosttyThemeParser.loadVVTheme(named: themeName)
        var theme = colorScheme == .dark ? MarkdownTheme.dark : MarkdownTheme.light
        theme.paragraphSpacing = Float(defaultsValue(for: markdownParagraphSpacingKey, fallback: defaultMarkdownParagraphSpacing))
        theme.headingSpacing = Float(defaultsValue(for: markdownHeadingSpacingKey, fallback: defaultMarkdownHeadingSpacing))
        theme.contentPadding = Float(defaultsValue(for: markdownContentPaddingKey, fallback: defaultMarkdownContentPadding))

        guard let terminalTheme else {
            return theme
        }

        let primaryText = simdColor(from: terminalTheme.textColor)
        let secondaryText = primaryText.withOpacity(colorScheme == .dark ? 0.74 : 0.68)
        let surface = simdColor(from: terminalTheme.backgroundColor).withOpacity(colorScheme == .dark ? 0.92 : 0.98)
        let elevatedSurface = simdColor(from: terminalTheme.currentLineColor).withOpacity(colorScheme == .dark ? 0.88 : 0.94)
        let divider = simdColor(from: GhosttyThemeParser.loadDividerColor(named: themeName))
            .withOpacity(colorScheme == .dark ? 0.34 : 0.18)
        let accent = simdColor(from: terminalTheme.cursorColor)

        theme.textColor = primaryText
        theme.headingColor = primaryText
        theme.linkColor = accent
        theme.codeColor = accent
        theme.codeBackgroundColor = surface
        theme.codeHeaderBackgroundColor = elevatedSurface
        theme.codeHeaderTextColor = secondaryText
        theme.codeHeaderDividerColor = divider.withOpacity(colorScheme == .dark ? 0.92 : 0.78)
        theme.codeCopyButtonBackground = elevatedSurface
        theme.codeCopyButtonTextColor = primaryText
        theme.codeBorderColor = divider
        theme.codeGutterBackgroundColor = elevatedSurface
        theme.codeGutterTextColor = secondaryText
        theme.blockQuoteColor = primaryText.withOpacity(0.9)
        theme.blockQuoteBorderColor = divider.withOpacity(colorScheme == .dark ? 0.92 : 0.82)
        theme.listBulletColor = secondaryText
        theme.checkboxCheckedColor = accent
        theme.checkboxUncheckedColor = secondaryText
        theme.thematicBreakColor = divider.withOpacity(colorScheme == .dark ? 0.96 : 0.88)
        theme.tableHeaderBackground = elevatedSurface
        theme.tableBackground = surface
        theme.tableBorderColor = divider
        theme.diagramBackground = surface
        theme.diagramNodeBackground = elevatedSurface
        theme.diagramNodeBorder = divider
        theme.diagramLineColor = divider.withOpacity(colorScheme == .dark ? 0.82 : 0.72)
        theme.diagramTextColor = primaryText
        theme.diagramNoteBackground = elevatedSurface
        theme.diagramNoteBorder = divider
        theme.diagramGroupBackground = surface.withOpacity(colorScheme == .dark ? 0.76 : 0.82)
        theme.diagramGroupBorder = divider
        theme.diagramActivationColor = elevatedSurface.withOpacity(colorScheme == .dark ? 0.9 : 0.94)
        theme.diagramActivationBorder = divider
        theme.mathColor = accent
        theme.strikethroughColor = secondaryText
        return theme
    }

    static func gitDiffRenderStyle(from rawValue: String) -> VVDiffRenderStyle {
        rawValue == "sideBySide" ? .sideBySide : .inline
    }

    static func gitDiffRenderStyleRawValue(for style: VVDiffRenderStyle) -> String {
        switch style {
        case .inline:
            return "inline"
        case .sideBySide:
            return "sideBySide"
        }
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.set(defaultDarkTheme, forKey: themeNameKey)
        defaults.set(defaultLightTheme, forKey: lightThemeNameKey)
        defaults.set(false, forKey: usePerAppearanceThemeKey)

        defaults.set(defaultTerminalFontFamily, forKey: terminalFontFamilyKey)
        defaults.set(defaultTerminalFontSize, forKey: terminalFontSizeKey)

        defaults.set(defaultCodeFontFamily, forKey: codeFontFamilyKey)
        defaults.set(defaultCodeFontSize, forKey: codeFontSizeKey)
        defaults.set(defaultDiffFontSize, forKey: diffFontSizeKey)
        defaults.set(defaultGitDiffRenderStyleRawValue, forKey: gitDiffRenderStyleKey)

        defaults.set(defaultMarkdownFontFamily, forKey: markdownFontFamilyKey)
        defaults.set(defaultMarkdownFontSize, forKey: markdownFontSizeKey)
        defaults.set(defaultMarkdownParagraphSpacing, forKey: markdownParagraphSpacingKey)
        defaults.set(defaultMarkdownHeadingSpacing, forKey: markdownHeadingSpacingKey)
        defaults.set(defaultMarkdownContentPadding, forKey: markdownContentPaddingKey)
    }

    static func defaultsValue(for key: String, fallback: Double) -> Double {
        let value = UserDefaults.standard.object(forKey: key) as? NSNumber
        return value?.doubleValue ?? fallback
    }

    static func simdColor(from color: NSColor) -> SIMD4<Float> {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return .rgba(Float(r), Float(g), Float(b), 1)
    }
}
