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

@main
struct aizenApp: App {
    @NSApplicationDelegateAdaptor(AizenAppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    @StateObject private var ghosttyApp = Ghostty.App()
    @FocusedValue(\.chatActions) var chatActions

    // Sparkle updater controller
    let updaterController: SPUStandardUpdaterController
    private let shortcutMonitor = KeyboardShortcutMonitor()
    @State var aboutWindow: NSWindow?

    // Terminal settings observers
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalThemeNameLight") private var terminalThemeNameLight = "Aizen Light"
    @AppStorage("terminalUsePerAppearanceTheme") private var terminalUsePerAppearanceTheme = false
    @AppStorage("terminalSessionPersistence") var sessionPersistence = false

    init() {
        // Initialize crash reporter early to catch startup crashes
        CrashReporter.shared.start()

        // Set launch source so libghostty knows to remove LANGUAGE env var
        // This makes terminal shells use system locale instead of macOS AppleLanguages
        setenv("GHOSTTY_MAC_LAUNCH_SOURCE", "app", 1)

        // Preload shell environment in background (speeds up agent session start)
        ShellEnvironment.preloadEnvironment()

        // Best-effort cleanup for orphaned ACP agents from a previous crash
        Task {
            await ProcessRegistry.shared.cleanupOrphanedProcesses()
        }

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
        _ = shortcutMonitor
    }

    var body: some Scene {
        WindowGroup {
            RootView(context: persistenceController.container.viewContext)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(ghosttyApp)
                .modifier(AppearanceModifier())
                .task {
                    LicenseStateStore.shared.start()
                }
                .task(id: "\(terminalFontName)\(terminalFontSize)\(terminalThemeName)\(terminalThemeNameLight)\(terminalUsePerAppearanceTheme)") {
                    ghosttyApp.reloadConfig()
                    await TmuxSessionRuntime.shared.updateConfig()
                }
                .task {
                    await cleanupOrphanedTmuxSessions()
                }
                .task {
                    await ChatSessionPersistence.shared.backfillSessionMetadata(
                        in: persistenceController.container.viewContext
                    )
                }
                .task {
                    await ChatSessionPersistence.shared.recoverDetachedSessionsFromLegacyScope(
                        in: persistenceController.container.viewContext
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands { appCommands }

    }
}
