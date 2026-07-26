//
//  aizenApp.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//
import ACP
import SwiftUI
import Sparkle
import AppKit
import os

@main
struct aizenApp: App {
    @NSApplicationDelegateAdaptor(AizenAppDelegate.self) var appDelegate

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
    init() {
        updaterController = Self.makeUpdaterController()
        configureStartup()
        _ = shortcutMonitor
        let host = reignitionHost
        Task { [host] in
            do {
                _ = try await host.prepareLegacyMigration()
                try await host.activate()
                do {
                    let agentConfiguration = try await DefaultACPAgentLaunchConfigurationResolver().launchConfiguration()
                    try await host.configureAgentLaunch(agentConfiguration)
                } catch {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "ReignitionAgentConfiguration")
                        .error("Host started without an ACP agent: \(error.localizedDescription, privacy: .public)")
                }
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
