//
//  GeneralSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log
import AppKit

struct GeneralSettingsView: View {
    let logger = Logger.settings

    @Binding var defaultEditor: String
    @StateObject var workspaceGraphQueryController: WorkspaceGraphQueryController

    // Appearance
    @AppStorage("appearanceMode") var appearanceMode: String = AppearanceMode.system.rawValue

    // Language
    @State var selectedLanguage: AppLanguage = .system
    @State var showingRestartAlert = false
    @State var hasLoadedLanguage = false

    // Default Apps
    @AppStorage("defaultTerminalBundleId") var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") var defaultEditorBundleId: String?
    @AppStorage("useCliEditor") var useCliEditor = false
    @AppStorage("defaultCloneLocation") var defaultCloneLocation = "~/.aizen/repos"
    @AppStorage("defaultWorkspaceId") var defaultWorkspaceId = ""

    // Layout
    @AppStorage("showChatTab") var showChatTab = true
    @AppStorage("showTerminalTab") var showTerminalTab = true
    @AppStorage("showFilesTab") var showFilesTab = true
    @AppStorage("showBrowserTab") var showBrowserTab = true

    // Toolbar
    @AppStorage("showOpenInApp") var showOpenInApp = true
    @AppStorage("showGitStatus") var showGitStatus = true
    @AppStorage("showXcodeBuild") var showXcodeBuild = true

    @ObservedObject var appDetector = AppDetector.shared
    @StateObject var tabConfig = TabConfigurationStore.shared

    @State var showingResetConfirmation = false
    @State var cliStatus = CLISymlinkService.status()
    @State var showingCLIAlert = false
    @State var cliAlertMessage = ""

    init(defaultEditor: Binding<String>) {
        _defaultEditor = defaultEditor
        _workspaceGraphQueryController = StateObject(
            wrappedValue: WorkspaceGraphQueryController(
                viewContext: PersistenceController.shared.container.viewContext
            )
        )
    }

    var workspaces: [Workspace] {
        workspaceGraphQueryController.workspaces
    }

    var body: some View {
        Form {
            appearanceSection

            languageSection

            defaultAppsSection

            projectsSection

            layoutSection

            toolbarSection

            cliSection

            resetSection
        }
        .formStyle(.grouped)
        .settingsSurface()
        .onAppear {
            loadCurrentLanguage()
            refreshCLIStatus()
        }
        .alert(LocalizedStringKey("settings.advanced.reset.alert.title"), isPresented: $showingResetConfirmation) {
            Button(LocalizedStringKey("settings.advanced.reset.alert.cancel"), role: .cancel) {}
            Button(LocalizedStringKey("settings.advanced.reset.alert.confirm"), role: .destructive) {
                resetApp()
            }
        } message: {
            Text("settings.advanced.reset.alert.message")
        }
        .alert("CLI Installation", isPresented: $showingCLIAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cliAlertMessage)
        }
        .alert("Restart Required", isPresented: $showingRestartAlert) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") {
                restartApp()
            }
        } message: {
            Text("Please restart the app to apply the language change.")
        }
    }

}
