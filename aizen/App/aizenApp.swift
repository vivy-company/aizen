//
//  aizenApp.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//
import ACP
import SwiftUI
import CoreData
import Sparkle
import AppKit
import os

@main
struct aizenApp: App {
    @NSApplicationDelegateAdaptor(AizenAppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    let reignitionHost = ReignitionHostComposition()
    @StateObject var ghosttyApp = Ghostty.App()
    @FocusedValue(\.chatActions) var chatActions

    // Sparkle updater controller
    let updaterController: SPUStandardUpdaterController
    private let shortcutMonitor = KeyboardShortcutMonitor()
    @State var aboutWindow: NSWindow?

    // Terminal settings observers
    @AppStorage("terminalFontName") var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") var terminalFontSize = 12.0
    @AppStorage("terminalThemeName") var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalThemeNameLight") var terminalThemeNameLight = "Aizen Light"
    @AppStorage("terminalUsePerAppearanceTheme") var terminalUsePerAppearanceTheme = false
    @AppStorage(TerminalPreferences.scrollbackLimitMBKey)
    var terminalScrollbackLimitMB = TerminalPreferences.defaultScrollbackLimitMB
    @AppStorage("terminalSessionPersistence") var sessionPersistence = false

    init() {
        updaterController = Self.makeUpdaterController()
        configureStartup()
        _ = shortcutMonitor
        let host = reignitionHost
        let legacyStoreURL = persistenceController.container.persistentStoreCoordinator.persistentStores.first?.url
        let legacyModelURL = Bundle.main.url(forResource: "aizen", withExtension: "momd")
        Task { [host, legacyStoreURL, legacyModelURL] in
            do {
                _ = try await host.prepareLegacyMigration(legacyStoreURL: legacyStoreURL, legacyModelURL: legacyModelURL)
                let agentConfiguration = try await DefaultACPAgentLaunchConfigurationResolver().launchConfiguration()
                try await host.activate(agentConfiguration: agentConfiguration)
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "ReignitionHostStartup")
                    .error("Reignition Host startup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var body: some Scene {
        appScene
    }
}
