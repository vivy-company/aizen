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
            detailContainer
        }
        .modifier(settingsViewLifecycle())
    }

}
