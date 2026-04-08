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

    /// Wrapper to hold reference to a surface for tracking
    /// Note: ghostty_surface_t is an opaque pointer, so we store it directly
    /// The surface is freed when the AizenTerminalSurfaceView is deallocated
    class SurfaceReference {
        let surface: ghostty_surface_t
        var isValid: Bool = true

        init(_ surface: ghostty_surface_t) {
            self.surface = surface
        }

        func invalidate() {
            isValid = false
        }
    }
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
            var runtime_cfg = ghostty_runtime_config_s(
                userdata: Unmanaged.passUnretained(self).toOpaque(),
                supports_selection_clipboard: true,
                wakeup_cb: { userdata in App.wakeup(userdata) },
                action_cb: { app, target, action in App.handleAction(app!, target: target, action: action) },
                read_clipboard_cb: { userdata, loc, state in App.readClipboard(userdata, location: loc, state: state) },
                confirm_read_clipboard_cb: { userdata, str, state, request in App.confirmReadClipboard(userdata, string: str, state: state, request: request) },
                write_clipboard_cb: { userdata, loc, content, count, confirm in
                    App.writeClipboard(userdata, location: loc, contents: content, count: count, confirm: confirm)
                },
                close_surface_cb: { userdata, processAlive in App.closeSurface(userdata, processAlive: processAlive) }
            )

            // Create config and load Aizen terminal settings
            guard let config = ghostty_config_new() else {
                Ghostty.logger.critical("ghostty_config_new failed")
                readiness = .error
                return
            }

            // Load config from settings
            loadConfigIntoGhostty(config)

            // Finalize config (required before use)
            ghostty_config_finalize(config)

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

            // Observe system appearance changes via DistributedNotificationCenter
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(systemAppearanceDidChange),
                name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil
            )

            // Observe in-app appearance setting changes
            appearanceSettingObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkAppearanceSettingChange()
                }
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardSelectionDidChange),
                name: NSTextInputContext.keyboardSelectionDidChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidResignActive),
                name: NSApplication.didResignActiveNotification,
                object: nil
            )

        }

        deinit {
            // Note: Cannot access @MainActor isolated properties in deinit
            // The app will be freed when the instance is deallocated
            // For proper cleanup, call a cleanup method before deinitialization
        }
    }
}
