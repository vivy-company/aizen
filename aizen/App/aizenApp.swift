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
        updaterController = Self.makeUpdaterController()
        configureStartup()
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
