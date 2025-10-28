//
//  aizenApp.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData

@main
struct aizenApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var ghosttyApp = Ghostty.App()
    @FocusedValue(\.terminalSplitActions) private var splitActions
    @FocusedValue(\.chatActions) private var chatActions

    // Terminal settings observers
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"

    var body: some Scene {
        WindowGroup {
            ContentView(context: persistenceController.container.viewContext)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(ghosttyApp)
                .onChange(of: terminalFontName) { _, _ in
                    Task { @MainActor in
                        ghosttyApp.reloadConfig()
                    }
                }
                .onChange(of: terminalFontSize) { _, _ in
                    Task { @MainActor in
                        ghosttyApp.reloadConfig()
                    }
                }
                .onChange(of: terminalBackgroundColor) { _, _ in
                    Task { @MainActor in
                        ghosttyApp.reloadConfig()
                    }
                }
                .onChange(of: terminalForegroundColor) { _, _ in
                    Task { @MainActor in
                        ghosttyApp.reloadConfig()
                    }
                }
                .onChange(of: terminalCursorColor) { _, _ in
                    Task { @MainActor in
                        ghosttyApp.reloadConfig()
                    }
                }
                .onChange(of: terminalSelectionBackground) { _, _ in
                    Task { @MainActor in
                        ghosttyApp.reloadConfig()
                    }
                }
                .onChange(of: terminalPalette) { _, _ in
                    Task { @MainActor in
                        ghosttyApp.reloadConfig()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
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
                .keyboardShortcut(.tab, modifiers: .shift)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
