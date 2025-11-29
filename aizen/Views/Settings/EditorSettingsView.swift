//
//  EditorSettingsView.swift
//  aizen
//
//  Settings for the code editor appearance and behavior
//

import SwiftUI

struct EditorSettingsView: View {
    @AppStorage("editorTheme") private var editorTheme: String = "Catppuccin Mocha"
    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 12.0
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0
    @AppStorage("editorWrapLines") private var editorWrapLines: Bool = true
    @AppStorage("editorShowMinimap") private var editorShowMinimap: Bool = false
    @AppStorage("editorShowGutter") private var editorShowGutter: Bool = true
    @AppStorage("editorIndentSpaces") private var editorIndentSpaces: Int = 4
    @AppStorage("editorTabBehavior") private var editorTabBehavior: String = "spaces"
    @AppStorage("showHiddenFiles") private var showHiddenFiles: Bool = false

    var availableFonts: [String] {
        NSFontManager.shared
            .availableFonts
            .sorted()
    }

    @State private var availableThemes: [String] = []

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $editorTheme) {
                    ForEach(availableThemes, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .disabled(availableThemes.isEmpty)
            } header: {
                Text("Theme")
            }

            Section {
                Picker("Font Family", selection: $editorFontFamily) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }

                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper(
                        "\(Int(editorFontSize)) pt",
                        value: $editorFontSize,
                        in: 8...24,
                        step: 1
                    )
                    .frame(width: 120)
                }

                HStack {
                    Text("Diff Font Size")
                    Spacer()
                    Stepper(
                        "\(Int(diffFontSize)) pt",
                        value: $diffFontSize,
                        in: 8...18,
                        step: 1
                    )
                    .frame(width: 120)
                }

                Text("Preview: \(editorFontFamily) \(Int(editorFontSize))pt")
                    .font(.custom(editorFontFamily, size: editorFontSize))
                    .monospaced()
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            } header: {
                Text("Font")
            }

            Section {
                Toggle("Line Numbers", isOn: $editorShowGutter)
                Toggle("Line Wrapping", isOn: $editorWrapLines)
                Toggle("Show Minimap", isOn: $editorShowMinimap)
            } header: {
                Text("Display")
            }

            Section {
                Picker("Tab Behavior", selection: $editorTabBehavior) {
                    Text("Spaces").tag("spaces")
                    Text("Tabs").tag("tabs")
                }
                .pickerStyle(.segmented)

                Picker("Indent Size", selection: $editorIndentSpaces) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Indentation")
            }

            Section {
                Toggle("Show Hidden Files", isOn: $showHiddenFiles)
            } header: {
                Text("File Browser")
            } footer: {
                Text("Show dotfiles and hidden folders in the file browser")
            }

            Section {
                Button("Reset to Defaults") {
                    editorTheme = "Catppuccin Mocha"
                    editorFontFamily = "Menlo"
                    editorFontSize = 12.0
                    diffFontSize = 11.0
                    editorWrapLines = true
                    editorShowMinimap = false
                    editorShowGutter = true
                    editorIndentSpaces = 4
                    editorTabBehavior = "spaces"
                    showHiddenFiles = false
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if availableThemes.isEmpty {
                availableThemes = GhosttyThemeParser.availableThemes()
            }
        }
    }
}

#Preview {
    EditorSettingsView()
        .frame(width: 600, height: 600)
}
