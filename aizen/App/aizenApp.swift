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

// App delegate to handle window restoration cleanup
class AizenAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable App Nap to prevent activation delays when clicking dock icon
        ProcessInfo.processInfo.disableAutomaticTermination("Aizen needs responsive activation")
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Prevent App Nap for responsive dock activation"
        )

        // Close duplicate main windows that macOS incorrectly restored
        // Keep only one main window (non-GitPanel window)
        DispatchQueue.main.async {
            let windows = NSApp.windows.filter { window in
                // Keep windows that are Git panels (we restore those ourselves)
                // or the first main window
                window.identifier != NSUserInterfaceItemIdentifier("GitPanelWindow") &&
                window.isVisible &&
                !window.isMiniaturized
            }

            // If there are multiple main windows, close the extras
            if windows.count > 1 {
                // Keep the first one, close the rest
                for window in windows.dropFirst() {
                    window.close()
                }
            }
        }

        // Best-effort CLI symlink install (non-blocking)
        DispatchQueue.global(qos: .utility).async {
            if CLISymlinkManager.installedSymlinkURL() == nil {
                _ = CLISymlinkManager.install()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.async {
            for url in urls {
                DeepLinkHandler.shared.handle(url)
            }
        }
    }
}

@main
struct aizenApp: App {
    @NSApplicationDelegateAdaptor(AizenAppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    @StateObject private var ghosttyApp = Ghostty.App()
    @FocusedValue(\.terminalSplitActions) private var splitActions
    @FocusedValue(\.chatActions) private var chatActions

    // Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController
    private let shortcutManager = KeyboardShortcutManager()
    @State private var aboutWindow: NSWindow?

    // Terminal settings observers
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

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
        _ = shortcutManager
    }

    var body: some Scene {
        WindowGroup {
            RootView(context: persistenceController.container.viewContext)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(ghosttyApp)
                .modifier(AppearanceModifier())
                .task {
                    LicenseManager.shared.start()
                }
                .task(id: "\(terminalFontName)\(terminalFontSize)\(terminalThemeName)") {
                    ghosttyApp.reloadConfig()
                    await TmuxSessionManager.shared.updateConfig()
                }
                .task {
                    await cleanupOrphanedTmuxSessions()
                }
                .task {
                    await SessionPersistenceService.shared.backfillSessionMetadata(
                        in: persistenceController.container.viewContext
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Aizen") {
                    showAboutWindow()
                }
            }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }

            CommandGroup(replacing: .appSettings) {
                Button {
                    SettingsWindowManager.shared.show()
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button {
                    installCLIFromMenu()
                } label: {
                    Label("Install CLI...", systemImage: "terminal")
                }
            }

            CommandGroup(after: .newItem) {
                Button("Active Environments...") {
                    ActiveWorktreesWindowManager.shared.show(context: persistenceController.container.viewContext)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Chat Sessions...") {
                    SessionsWindowManager.shared.show(context: persistenceController.container.viewContext)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

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
                Button("Join Discord Community") {
                    if let url = URL(string: "https://discord.gg/zemMZtrkSb") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("View on GitHub") {
                    if let url = URL(string: "https://github.com/vivy-company/aizen") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Report an Issue") {
                    if let url = URL(string: "https://github.com/vivy-company/aizen/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

    }

    // MARK: - About Window

    private func showAboutWindow() {
        if let existingWindow = aboutWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let aboutView = AboutView()
            .modifier(AppearanceModifier())
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Aizen"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        aboutWindow = window
    }

    private func installCLIFromMenu() {
        let result = CLISymlinkManager.install()
        let alert = NSAlert()
        alert.messageText = "CLI Installation"
        alert.informativeText = result.message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Settings Window

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
