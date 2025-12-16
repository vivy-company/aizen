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
    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    init() {
        // Set launch source so libghostty knows to remove LANGUAGE env var
        // This makes terminal shells use system locale instead of macOS AppleLanguages
        setenv("GHOSTTY_MAC_LAUNCH_SOURCE", "app", 1)

        // Preload shell environment in background (speeds up agent session start)
        ShellEnvironment.preloadEnvironment()

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
                .task {
                    await cleanupOrphanedTmuxSessions()
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

            CommandGroup(replacing: .help) {
                Button {
                    if let url = URL(string: "https://discord.gg/eKW7GNesuS") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Join Discord Community", image: "DiscordLogo")
                }
            }
        }

        Settings {
            SettingsView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }

    // MARK: - tmux Session Cleanup

    /// Clean up orphaned tmux sessions that no longer have matching Core Data panes
    private func cleanupOrphanedTmuxSessions() async {
        guard sessionPersistence else { return }

        let context = persistenceController.container.viewContext
        var validPaneIds = Set<String>()

        // Fetch all terminal sessions and extract their pane IDs
        await context.perform {
            let request: NSFetchRequest<TerminalSession> = TerminalSession.fetchRequest()
            do {
                let sessions = try context.fetch(request)
                for session in sessions {
                    if let layoutJSON = session.splitLayout,
                       let layout = SplitLayoutHelper.decode(layoutJSON) {
                        validPaneIds.formUnion(layout.allPaneIds())
                    }
                }
            } catch {
                // Silently fail - orphan cleanup is best-effort
            }
        }

        await TmuxSessionManager.shared.cleanupOrphanedSessions(validPaneIds: validPaneIds)
    }
}
