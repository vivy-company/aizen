//
//  AppearanceSettingsView.swift
//  aizen
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceSettings.themeNameKey) private var themeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) private var lightThemeName = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var usePerAppearanceTheme = false

    @AppStorage(AppearanceSettings.terminalFontFamilyKey) private var terminalFontFamily = AppearanceSettings.defaultTerminalFontFamily
    @AppStorage(AppearanceSettings.terminalFontSizeKey) private var terminalFontSize = AppearanceSettings.defaultTerminalFontSize

    @AppStorage(AppearanceSettings.codeFontFamilyKey) private var codeFontFamily = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.codeFontSizeKey) private var codeFontSize = AppearanceSettings.defaultCodeFontSize
    @AppStorage(AppearanceSettings.diffFontSizeKey) private var diffFontSize = AppearanceSettings.defaultDiffFontSize

    @AppStorage(AppearanceSettings.markdownFontFamilyKey) private var markdownFontFamily = AppearanceSettings.defaultMarkdownFontFamily
    @AppStorage(AppearanceSettings.markdownFontSizeKey) private var markdownFontSize = AppearanceSettings.defaultMarkdownFontSize
    @AppStorage(AppearanceSettings.markdownParagraphSpacingKey) private var markdownParagraphSpacing = AppearanceSettings.defaultMarkdownParagraphSpacing
    @AppStorage(AppearanceSettings.markdownHeadingSpacingKey) private var markdownHeadingSpacing = AppearanceSettings.defaultMarkdownHeadingSpacing
    @AppStorage(AppearanceSettings.markdownContentPaddingKey) private var markdownContentPadding = AppearanceSettings.defaultMarkdownContentPadding

    @State private var availableThemes: [String] = []
    @State private var monospaceFonts: [String] = []
    @State private var readableFonts: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle("Use different themes for Light/Dark mode", isOn: $usePerAppearanceTheme)

                if usePerAppearanceTheme {
                    Picker("Dark Theme", selection: $themeName) {
                        ForEach(availableThemes, id: \.self) { theme in
                            Text(theme).tag(theme)
                        }
                    }
                    .disabled(availableThemes.isEmpty)

                    Picker("Light Theme", selection: $lightThemeName) {
                        ForEach(availableThemes, id: \.self) { theme in
                            Text(theme).tag(theme)
                        }
                    }
                    .disabled(availableThemes.isEmpty)
                } else {
                    Picker("Theme", selection: $themeName) {
                        ForEach(availableThemes, id: \.self) { theme in
                            Text(theme).tag(theme)
                        }
                    }
                    .disabled(availableThemes.isEmpty)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Ghostty themes are the shared color source for app surfaces, terminal, code, diff, and markdown.")
            }

            Section {
                Picker("Font Family", selection: $terminalFontFamily) {
                    ForEach(monospaceFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .disabled(monospaceFonts.isEmpty)

                stepperRow(
                    title: "Font Size",
                    value: $terminalFontSize,
                    range: AppearanceSettings.fontSizeRange
                )
            } header: {
                Text("Terminal Typography")
            }

            Section {
                Picker("Font Family", selection: $codeFontFamily) {
                    ForEach(monospaceFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .disabled(monospaceFonts.isEmpty)

                stepperRow(
                    title: "Font Size",
                    value: $codeFontSize,
                    range: AppearanceSettings.fontSizeRange
                )

                stepperRow(
                    title: "Diff Font Size",
                    value: $diffFontSize,
                    range: 8...18
                )
            } header: {
                Text("Code Typography")
            }

            Section {
                Picker("Font Family", selection: $markdownFontFamily) {
                    ForEach(readableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .disabled(readableFonts.isEmpty)

                stepperRow(
                    title: "Font Size",
                    value: $markdownFontSize,
                    range: AppearanceSettings.markdownFontSizeRange
                )

                stepperRow(
                    title: "Paragraph Spacing",
                    value: $markdownParagraphSpacing,
                    range: AppearanceSettings.markdownParagraphSpacingRange
                )

                stepperRow(
                    title: "Heading Spacing",
                    value: $markdownHeadingSpacing,
                    range: AppearanceSettings.markdownHeadingSpacingRange
                )

                stepperRow(
                    title: "Content Padding",
                    value: $markdownContentPadding,
                    range: AppearanceSettings.markdownContentPaddingRange
                )
            } header: {
                Text("Markdown Typography")
            }

            Section {
                Button("Reset Appearance to Defaults") {
                    AppearanceSettings.reset()
                }
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .onAppear {
            if availableThemes.isEmpty {
                availableThemes = GhosttyThemeParser.availableThemes()
            }
            if monospaceFonts.isEmpty {
                monospaceFonts = AppearanceSettings.monospaceFonts()
            }
            if readableFonts.isEmpty {
                readableFonts = AppearanceSettings.readableFonts()
            }
        }
    }

    @ViewBuilder
    private func stepperRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Text("\(Int(value.wrappedValue)) pt")
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)
            Stepper("", value: value, in: range, step: 1)
                .labelsHidden()
        }
    }
}

#Preview {
    AppearanceSettingsView()
        .frame(width: 900, height: 640)
}
