//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

private extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "general"
    case terminal = "terminal"
    case editor = "editor"
    case appearance = "appearance"
    case agents = "agents"
    case advanced = "advanced"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return String(localized: "settings.general.title")
        case .terminal: return String(localized: "settings.terminal.title")
        case .editor: return String(localized: "settings.editor.title")
        case .appearance: return "Appearance"
        case .agents: return String(localized: "settings.agents.title")
        case .advanced: return String(localized: "settings.advanced.title")
        }
    }
    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .terminal: return "terminal"
        case .editor: return "doc.text"
        case .appearance: return "paintpalette"
        case .agents: return "brain"
        case .advanced: return "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @AppStorage("defaultEditor") private var defaultEditor = "code"
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    @State private var selectedSection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
            .removingSidebarToggle()
        } detail: {
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsView(defaultEditor: $defaultEditor)
                        .navigationTitle(SettingsSection.general.title)
                case .terminal:
                    TerminalSettingsView(
                        fontName: $terminalFontName,
                        fontSize: $terminalFontSize
                    )
                    .navigationTitle(SettingsSection.terminal.title)
                case .editor:
                    EditorSettingsView()
                        .navigationTitle(SettingsSection.editor.title)
                case .appearance:
                    AppearanceSettingsView()
                        .navigationTitle(SettingsSection.appearance.title)
                case .agents:
                    AgentsSettingsView(defaultACPAgent: $defaultACPAgent)
                        .navigationTitle(SettingsSection.agents.title)
                case .advanced:
                    AdvancedSettingsView()
                        .navigationTitle(SettingsSection.advanced.title)
                case .none:
                    GeneralSettingsView(defaultEditor: $defaultEditor)
                        .navigationTitle(SettingsSection.general.title)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 750, height: 550)
    }
}
