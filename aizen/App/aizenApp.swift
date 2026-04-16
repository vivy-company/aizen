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
    }

    var body: some Scene {
        appScene
    }
}
