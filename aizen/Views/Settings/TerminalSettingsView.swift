//
//  TerminalSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct TerminalSettingsView: View {
    private let logger = Logger.settings
    @Binding var fontName: String
    @Binding var fontSize: Double
    @AppStorage("terminalThemeName") private var themeName = "Catppuccin Mocha"
    @AppStorage("terminalNotificationsEnabled") private var terminalNotificationsEnabled = true
    @AppStorage("terminalProgressEnabled") private var terminalProgressEnabled = true

    @StateObject private var presetManager = TerminalPresetManager.shared
    @State private var availableFonts: [String] = []
    @State private var themeNames: [String] = []
    @State private var showingAddPreset = false
    @State private var editingPreset: TerminalPreset?

    private static var themesPath: String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        return (resourcePath as NSString).appendingPathComponent("ghostty/themes")
    }

    private func loadSystemFonts() -> [String] {
        let fontManager = NSFontManager.shared
        let monospaceFonts = fontManager.availableFontFamilies.filter { familyName in
            guard let font = NSFont(name: familyName, size: 12) else { return false }
            return font.isFixedPitch
        }
        return monospaceFonts.sorted()
    }

    private func loadThemeNames() -> [String] {
        guard let themesPath = Self.themesPath else {
            logger.error("Unable to locate themes directory")
            return []
        }

        guard let themeFiles = try? FileManager.default.contentsOfDirectory(atPath: themesPath) else {
            logger.error("Unable to read themes from \(themesPath)")
            return []
        }

        // Filter out directories and hidden files
        return themeFiles.filter { file in
            let path = (themesPath as NSString).appendingPathComponent(file)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return !isDir.boolValue && !file.hasPrefix(".")
        }.sorted()
    }

    var body: some View {
        Form {
            Section(LocalizedStringKey("settings.terminal.font.section")) {
                Picker(LocalizedStringKey("settings.terminal.font.picker"), selection: $fontName) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .disabled(availableFonts.isEmpty)

                HStack {
                    Text(String(format: NSLocalizedString("settings.terminal.font.size", comment: ""), Int(fontSize)))
                        .frame(width: 120, alignment: .leading)

                    Slider(value: $fontSize, in: 8...24, step: 1)

                    Stepper("", value: $fontSize, in: 8...24, step: 1)
                        .labelsHidden()
                }
            }

            Section(LocalizedStringKey("settings.terminal.theme.section")) {
                Picker(LocalizedStringKey("settings.terminal.theme.picker"), selection: $themeName) {
                    ForEach(themeNames, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .disabled(themeNames.isEmpty)
            }

            Section("Terminal Behavior") {
                Toggle("Enable terminal notifications", isOn: $terminalNotificationsEnabled)
                Toggle("Show progress overlays", isOn: $terminalProgressEnabled)
            }

            Section {
                ForEach(presetManager.presets) { preset in
                    HStack(spacing: 12) {
                        Image(systemName: preset.icon)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .fontWeight(.medium)
                            Text(preset.command)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            editingPreset = preset
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            presetManager.deletePreset(id: preset.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { source, destination in
                    presetManager.movePreset(from: source, to: destination)
                }

                Button {
                    showingAddPreset = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Add Preset")
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Terminal Presets")
            } footer: {
                Text("Presets appear in the empty terminal state and when long-pressing the + button")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if availableFonts.isEmpty {
                availableFonts = loadSystemFonts()
            }
            if themeNames.isEmpty {
                themeNames = loadThemeNames()
            }
        }
        .sheet(isPresented: $showingAddPreset) {
            TerminalPresetFormView(
                onSave: { _ in },
                onCancel: {}
            )
        }
        .sheet(item: $editingPreset) { preset in
            TerminalPresetFormView(
                existingPreset: preset,
                onSave: { _ in },
                onCancel: {}
            )
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
