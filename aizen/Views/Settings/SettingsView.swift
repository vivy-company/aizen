//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultEditor") private var defaultEditor = "code"
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    var body: some View {
        TabView {
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .tabItem {
                    Label("settings.general.title", systemImage: "gear")
                }
                .tag("general")

            TerminalSettingsView(
                fontName: $terminalFontName,
                fontSize: $terminalFontSize
            )
            .tabItem {
                Label("settings.terminal.title", systemImage: "terminal")
            }
            .tag("terminal")

            EditorSettingsView()
                .tabItem {
                    Label("settings.editor.title", systemImage: "doc.text")
                }
                .tag("editor")

            AgentsSettingsView(defaultACPAgent: $defaultACPAgent)
                .tabItem {
                    Label("settings.agents.title", systemImage: "brain")
                }
                .tag("agents")

            AdvancedSettingsView()
                .tabItem {
                    Label("settings.advanced.title", systemImage: "gearshape.2")
                }
                .tag("advanced")
        }
        .frame(width: 600, height: 600)
    }
}
