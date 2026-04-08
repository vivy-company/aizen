//
//  Ghostty.App.swift
//  aizen
//
//  Minimal Ghostty app wrapper - Phase 1: Basic lifecycle
//

import Foundation
import AppKit
import Combine
import GhosttyKit
import OSLog
import SwiftUI

// MARK: - Ghostty Namespace

enum Ghostty {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "Ghostty")
}

// MARK: - Ghostty.App

extension Ghostty {
    /// Minimal wrapper for ghostty_app_t lifecycle management
    class App: ObservableObject {
        enum Readiness: String {
            case loading, error, ready
        }

        // MARK: - Published Properties

        /// The ghostty app instance
        @Published var app: ghostty_app_t? = nil

        /// Readiness state
        @Published var readiness: Readiness = .loading

        /// Track active surfaces for config propagation
        var activeSurfaces: [Ghostty.SurfaceReference] = []

        /// Track last known appearance to detect changes
        var lastKnownAppearance: NSAppearance.Name?

        /// Track last known theme to detect changes
        var lastKnownTheme: String?

        /// Observer for in-app appearance setting changes
        var appearanceSettingObserver: NSObjectProtocol?

        // MARK: - Terminal Settings from AppStorage

        @AppStorage(AppearanceSettings.terminalFontFamilyKey) var terminalFontName = AppearanceSettings.defaultTerminalFontFamily
        @AppStorage(AppearanceSettings.terminalFontSizeKey) var terminalFontSize = AppearanceSettings.defaultTerminalFontSize
        @AppStorage(AppearanceSettings.themeNameKey) var terminalThemeName = AppearanceSettings.defaultDarkTheme
        @AppStorage(AppearanceSettings.lightThemeNameKey) var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
        @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) var usePerAppearanceTheme = false
        @AppStorage("appearanceMode") private var appearanceMode = "system"

        var effectiveThemeName: String {
            if !usePerAppearanceTheme {
                return terminalThemeName
            }
            return AppearanceSettings.effectiveThemeName(appearanceMode: appearanceMode)
        }

        // MARK: - Initialization

        init() {
            // CRITICAL: Initialize libghostty first
            let initResult = ghostty_init(0, nil)
            if initResult != GHOSTTY_SUCCESS {
                Ghostty.logger.critical("ghostty_init failed with code: \(initResult)")
                readiness = .error
                return
            }

            // Create runtime config with callbacks
            var runtime_cfg = makeRuntimeConfig()

            // Create config and load Aizen terminal settings
            guard let config = makeInitialConfig() else { return }

            // Create the ghostty app
            guard let app = ghostty_app_new(&runtime_cfg, config) else {
                Ghostty.logger.critical("ghostty_app_new failed")
                ghostty_config_free(config)
                readiness = .error
                return
            }

            // Free config after app creation (app clones it)
            ghostty_config_free(config)

            // CRITICAL: Unset XDG_CONFIG_HOME after app creation
            // If left set, fish will look for config.fish in the temp directory instead of ~/.config
            unsetenv("XDG_CONFIG_HOME")

            self.app = app
            ghostty_app_set_focus(app, NSApp.isActive)
            self.readiness = .ready

            // Store initial appearance and theme
            lastKnownAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            lastKnownTheme = effectiveThemeName

            installObservers()
        }

        deinit {
            // Note: Cannot access @MainActor isolated properties in deinit
            // The app will be freed when the instance is deallocated
            // For proper cleanup, call a cleanup method before deinitialization
        }
    }
}
