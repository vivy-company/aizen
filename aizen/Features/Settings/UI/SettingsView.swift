//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

// MARK: - Settings Selection

enum SettingsSelection: Hashable {
    case general
    case appearance
    case transcription
    case pro
    case git
    case terminal
    case editor
    case agent(String) // agent id
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("defaultEditor") var defaultEditor = "code"
    @AppStorage("defaultACPAgent") var defaultACPAgent = AgentRegistry.defaultAgentID
    @State var selection: SettingsSelection? = .general
    @State var agents: [AgentMetadata] = []
    @State var showingAddCustomAgent = false
    @StateObject var licenseManager = LicenseStateStore.shared

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            if #available(macOS 14.0, *) {
                NavigationStack {
                    detailView
                }
            } else {
                NavigationStack {
                    detailView
                }
            }
        }
        .toolbar {
            // Forces creation of an NSToolbar so the window's unified toolbar style applies.
            ToolbarItem(placement: .principal) { Text("") }
        }
        .settingsSheetChrome()
        .settingsNativeToolbarGlass()
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 500)
        .onAppear {
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPro)) { _ in
            selection = .pro
        }
        .sheet(isPresented: $showingAddCustomAgent) {
            CustomAgentFormView(
                onSave: { _ in
                    loadAgents()
                },
                onCancel: {}
            )
        }
    }

    private func loadAgents() {
        let updatedAgents = AgentRegistry.shared.getAllAgents()
        agents = updatedAgents

        if case .agent(let agentId) = selection,
           !updatedAgents.contains(where: { $0.id == agentId }) {
            selection = updatedAgents.first.map { .agent($0.id) } ?? .general
        }
    }

}
