//
//  EditorSettingsView.swift
//  aizen
//
//  Settings for the code editor appearance and behavior
//

import SwiftUI

struct EditorSettingsView: View {
    @AppStorage("editorWrapLines") private var editorWrapLines: Bool = true
    @AppStorage("editorShowGutter") private var editorShowGutter: Bool = true
    @AppStorage("editorIndentSpaces") private var editorIndentSpaces: Int = 4
    @AppStorage("showHiddenFiles") private var showHiddenFiles: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Line Numbers", isOn: $editorShowGutter)
                Toggle("Line Wrapping", isOn: $editorWrapLines)
            } header: {
                Text("Display")
            }

            Section {
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
                    editorWrapLines = true
                    editorShowGutter = true
                    editorIndentSpaces = 4
                    showHiddenFiles = false
                }
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EditorSettingsView()
        .frame(width: 600, height: 600)
}
