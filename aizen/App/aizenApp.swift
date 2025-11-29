//
//  aizenApp.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData
import Sparkle

@main
struct aizenApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var ghosttyApp = Ghostty.App()
    @FocusedValue(\.terminalSplitActions) private var splitActions
    @FocusedValue(\.chatActions) private var chatActions

    // Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController
    private let shortcutManager = KeyboardShortcutManager()

    // Terminal settings observers
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalThemeName") private var terminalThemeName = "Catppuccin Mocha"

    init() {
        // Set launch source so libghostty knows to remove LANGUAGE env var
        // This makes terminal shells use system locale instead of macOS AppleLanguages
        setenv("GHOSTTY_MAC_LAUNCH_SOURCE", "app", 1)

        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Enable automatic update checks
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.updateCheckInterval = 3600 // Check every hour

        // Shortcut manager handles global shortcuts
        _ = shortcutManager
    }

    var body: some Scene {
        WindowGroup {
            RootView(context: persistenceController.container.viewContext)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(ghosttyApp)
                .task(id: "\(terminalFontName)\(terminalFontSize)\(terminalThemeName)") {
                    ghosttyApp.reloadConfig()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }

            CommandGroup(after: .newItem) {
                Button("Split Right") {
                    splitActions?.splitHorizontal()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Down") {
                    splitActions?.splitVertical()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Close Pane") {
                    splitActions?.closePane()
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Cycle Mode") {
                    chatActions?.cycleModeForward()
                }
            }
        }

        Settings {
            SettingsView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
