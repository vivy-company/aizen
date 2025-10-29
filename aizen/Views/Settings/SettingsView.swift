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
    @AppStorage("acpAgentPath_claude") private var claudePath = ""
    @AppStorage("acpAgentPath_codex") private var codexPath = ""
    @AppStorage("acpAgentPath_gemini") private var geminiPath = ""
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    @State private var testingAgent: String? = nil
    @State private var testResult: String? = nil

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

            AgentsSettingsView(
                defaultACPAgent: $defaultACPAgent,
                claudePath: $claudePath,
                codexPath: $codexPath,
                geminiPath: $geminiPath,
                testingAgent: $testingAgent,
                testResult: $testResult
            )
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
