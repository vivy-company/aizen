//
//  Ghostty.App.swift
//  aizen
//
//  Minimal Ghostty app wrapper - Phase 1: Basic lifecycle
//

import Foundation
import AppKit
import Combine
import OSLog
import SwiftUI

// MARK: - Ghostty Namespace

enum Ghostty {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "Ghostty")

    /// Wrapper to hold reference to a surface for tracking
    /// Note: ghostty_surface_t is an opaque pointer, so we store it directly
    /// The surface is freed when the GhosttyTerminalView is deallocated
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
    @MainActor
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
        private var activeSurfaces: [Ghostty.SurfaceReference] = []

        /// Track last known appearance to detect changes
        private var lastKnownAppearance: NSAppearance.Name?

        /// Track last known theme to detect changes
        private var lastKnownTheme: String?

        /// Observer for in-app appearance setting changes
        private var appearanceSettingObserver: NSObjectProtocol?

        // MARK: - Terminal Settings from AppStorage

        @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
        @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
        @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
        @AppStorage("terminalThemeNameLight") private var terminalThemeNameLight = "Aizen Light"
        @AppStorage("terminalUsePerAppearanceTheme") private var usePerAppearanceTheme = false
        @AppStorage("appearanceMode") private var appearanceMode = "system"

        private var effectiveThemeName: String {
            guard usePerAppearanceTheme else { return terminalThemeName }

            // Check in-app appearance setting first
            switch appearanceMode {
            case "light":
                return terminalThemeNameLight
            case "dark":
                return terminalThemeName
            default:
                // System mode - follow actual system appearance
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark ? terminalThemeName : terminalThemeNameLight
            }
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
                action_cb: { app, target, action in App.action(app!, target: target, action: action) },
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
                self?.checkAppearanceSettingChange()
            }

            Ghostty.logger.info("Ghostty app initialized successfully")
        }

        @objc private func systemAppearanceDidChange(_ notification: Notification) {
            handleAppearanceChange()
        }

        private func handleAppearanceChange() {
            guard usePerAppearanceTheme else { return }

            let currentAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            guard currentAppearance != lastKnownAppearance else { return }

            lastKnownAppearance = currentAppearance
            reloadIfThemeChanged()
        }

        private func checkAppearanceSettingChange() {
            guard usePerAppearanceTheme else { return }
            reloadIfThemeChanged()
        }

        private func reloadIfThemeChanged() {
            let newTheme = effectiveThemeName
            guard newTheme != lastKnownTheme else { return }

            lastKnownTheme = newTheme
            Ghostty.logger.info("Theme changed, reloading terminal config with theme: \(newTheme)")
            reloadConfig()
        }

        deinit {
            // Note: Cannot access @MainActor isolated properties in deinit
            // The app will be freed when the instance is deallocated
            // For proper cleanup, call a cleanup method before deinitialization
        }

        // MARK: - App Operations

        /// Clean up the ghostty app resources
        func cleanup() {
            DistributedNotificationCenter.default().removeObserver(self)

            if let observer = appearanceSettingObserver {
                NotificationCenter.default.removeObserver(observer)
                appearanceSettingObserver = nil
            }

            if let app = self.app {
                ghostty_app_free(app)
                self.app = nil
            }
        }

        func appTick() {
            guard let app = self.app else { return }
            ghostty_app_tick(app)
        }

        /// Register a surface for config update tracking
        /// Returns the surface reference that should be stored by the view
        @discardableResult
        func registerSurface(_ surface: ghostty_surface_t) -> Ghostty.SurfaceReference {
            let ref = Ghostty.SurfaceReference(surface)
            activeSurfaces.append(ref)
            // Clean up invalid surfaces
            activeSurfaces = activeSurfaces.filter { $0.isValid }
            return ref
        }

        /// Unregister a surface when it's being deallocated
        func unregisterSurface(_ ref: Ghostty.SurfaceReference) {
            ref.invalidate()
            activeSurfaces = activeSurfaces.filter { $0.isValid }
        }

        /// Reload configuration (call when settings change)
        func reloadConfig() {
            guard let app = self.app else { return }

            // Create new config with updated settings
            guard let config = ghostty_config_new() else {
                Ghostty.logger.error("ghostty_config_new failed during reload")
                return
            }

            // Load config from settings
            loadConfigIntoGhostty(config)

            // Finalize config (required before use)
            ghostty_config_finalize(config)

            // Update the app config
            ghostty_app_update_config(app, config)

            // Propagate config to all existing surfaces
            for surfaceRef in activeSurfaces where surfaceRef.isValid {
                ghostty_surface_update_config(surfaceRef.surface, config)
            }

            // Clean up invalid surfaces
            activeSurfaces = activeSurfaces.filter { $0.isValid }

            ghostty_config_free(config)

            // Unset XDG_CONFIG_HOME so it doesn't affect fish/shell config loading
            unsetenv("XDG_CONFIG_HOME")

            Ghostty.logger.info("Configuration reloaded and propagated to \(self.activeSurfaces.count) surfaces")
        }

        // MARK: - Private Helpers

        /// Generate and load config content into a ghostty_config_t
        private func loadConfigIntoGhostty(_ config: ghostty_config_t) {
            // Create temp config directory and use Ghostty themes
            let tempDir = NSTemporaryDirectory()
            let ghosttyConfigDir = (tempDir as NSString).appendingPathComponent(".config/ghostty")
            let configFilePath = (ghosttyConfigDir as NSString).appendingPathComponent("config")

            do {
                try FileManager.default.createDirectory(atPath: ghosttyConfigDir, withIntermediateDirectories: true)

                // Detect shell for integration
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                let shellName = (shell as NSString).lastPathComponent

                // Create config with font settings, shell integration, and theme
                let configContent = """
                font-family = \(terminalFontName)
                font-size = \(Int(terminalFontSize))
                window-inherit-font-size = false
                window-padding-balance = true
                window-padding-x = 0
                window-padding-y = 0
                window-padding-color = extend-always

                # Enable shell integration (resources dir auto-detected from app bundle)
                shell-integration = \(shellName)
                shell-integration-features = no-cursor,sudo,title

                # Cursor
                cursor-style-blink = true

                theme = \(effectiveThemeName)

                # Disable audible bell
                audible-bell = false

                # Custom keybinds
                keybind = shift+enter=text:\\n

                """

                Ghostty.logger.info("Loading Ghostty theme: \(self.effectiveThemeName)")

                try configContent.write(toFile: configFilePath, atomically: true, encoding: .utf8)

                // Set XDG_CONFIG_HOME to our temp directory
                // With bundle ID "com.aizen.terminal", Ghostty will look for config at:
                // ~/Library/Application Support/com.aizen.terminal/config (won't exist)
                // So it will use our XDG config only
                setenv("XDG_CONFIG_HOME", (tempDir as NSString).appendingPathComponent(".config"), 1)

                // Load default files - will load our XDG config
                // Will NOT load user's Ghostty config (com.mitchellh.ghostty) since bundle ID is different
                ghostty_config_load_default_files(config)

                Ghostty.logger.info("Loaded Aizen terminal settings - Font: \(self.terminalFontName) \(Int(self.terminalFontSize))pt, Theme: \(self.effectiveThemeName)")
            } catch {
                Ghostty.logger.warning("Failed to write config: \(error)")
            }
        }

        // MARK: - Callbacks (macOS)

        static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
            guard let userdata = userdata else { return }
            let state = Unmanaged<App>.fromOpaque(userdata).takeUnretainedValue()

            // Schedule tick on main thread
            DispatchQueue.main.async {
                state.appTick()
            }
        }

        static func action(_ app: ghostty_app_t, target: ghostty_target_s, action: ghostty_action_s) -> Bool {
            // Get the terminal view from surface userdata if target is a surface
            let terminalView: GhosttyTerminalView? = {
                guard target.tag == GHOSTTY_TARGET_SURFACE else { return nil }
                let surface = target.target.surface
                guard let userdata = ghostty_surface_userdata(surface) else { return nil }
                return Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
            }()

            switch action.tag {
            case GHOSTTY_ACTION_SET_TITLE:
                // Window/tab title change
                if let titlePtr = action.action.set_title.title {
                    let title = String(cString: titlePtr)
                    Ghostty.logger.info("Title changed: \(title)")

                    // Propagate to terminal view callback
                    DispatchQueue.main.async {
                        terminalView?.onTitleChange?(title)
                    }
                }
                return true

            case GHOSTTY_ACTION_PWD:
                // Working directory change
                if let pwdPtr = action.action.pwd.pwd {
                    let pwd = String(cString: pwdPtr)
                    Ghostty.logger.info("PWD changed: \(pwd)")
                }
                return true

            case GHOSTTY_ACTION_PROMPT_TITLE:
                // Prompt title update (for shell integration)
                Ghostty.logger.debug("Prompt title action received")
                return true

            case GHOSTTY_ACTION_PROGRESS_REPORT:
                let report = action.action.progress_report
                let state = GhosttyProgressState(cState: report.state)
                let value = report.progress >= 0 ? Int(report.progress) : nil
                DispatchQueue.main.async {
                    terminalView?.onProgressReport?(state, value)
                }
                return true

            case GHOSTTY_ACTION_CELL_SIZE:
                // Cell size update - used for row-to-pixel conversion in scrollbar
                let cellSize = action.action.cell_size
                let backingSize = NSSize(width: Double(cellSize.width), height: Double(cellSize.height))
                DispatchQueue.main.async {
                    guard let terminalView = terminalView else { return }
                    // Convert from backing (pixel) coordinates to points
                    terminalView.cellSize = terminalView.convertFromBacking(backingSize)
                }
                return true

            case GHOSTTY_ACTION_SCROLLBAR:
                // Scrollbar state update - post notification for scroll view
                let scrollbar = Ghostty.Action.Scrollbar(c: action.action.scrollbar)
                NotificationCenter.default.post(
                    name: .ghosttyDidUpdateScrollbar,
                    object: terminalView,
                    userInfo: [Notification.Name.ScrollbarKey: scrollbar]
                )
                return true

            default:
                // Log unhandled actions
                Ghostty.logger.debug("Action received: \(action.tag.rawValue) on target: \(target.tag.rawValue)")
                return false
            }
        }

        static func readClipboard(_ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) {
            // userdata is the GhosttyTerminalView instance
            guard let userdata = userdata else { return }
            let terminalView = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = terminalView.surface?.unsafeCValue else { return }

            // Read from macOS clipboard
            let clipboardString = Clipboard.readString() ?? ""

            // Complete the clipboard request by providing data to Ghostty
            clipboardString.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }

            Ghostty.logger.debug("Read clipboard: \(clipboardString.prefix(50))...")
        }

        static func confirmReadClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            string: UnsafePointer<CChar>?,
            state: UnsafeMutableRawPointer?,
            request: ghostty_clipboard_request_e
        ) {
            // Clipboard read confirmation
            // For security, apps can confirm before allowing clipboard access
            // For now, just log it
            Ghostty.logger.debug("Clipboard read confirmation requested")
        }

        static func writeClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            location: ghostty_clipboard_e,
            contents: UnsafePointer<ghostty_clipboard_content_s>?,
            count: Int,
            confirm: Bool
        ) {
            guard let contents = contents, count > 0 else { return }

            // The runtime passes an array of clipboard entries; prefer the first
            // textual entry. The API does not supply a byte length, so we treat
            // the data as a null-terminated UTF-8 C string.
            for idx in 0..<count {
                let entry = contents.advanced(by: idx).pointee
                guard let dataPtr = entry.data else { continue }

                var string = String(cString: dataPtr)
                if !string.isEmpty {
                    // Apply copy transformations from settings
                    let settings = TerminalCopySettings(
                        trimTrailingWhitespace: UserDefaults.standard.object(forKey: "terminalCopyTrimTrailingWhitespace") as? Bool ?? true,
                        collapseBlankLines: UserDefaults.standard.bool(forKey: "terminalCopyCollapseBlankLines"),
                        stripShellPrompts: UserDefaults.standard.bool(forKey: "terminalCopyStripShellPrompts"),
                        flattenCommands: UserDefaults.standard.bool(forKey: "terminalCopyFlattenCommands"),
                        removeBoxDrawing: UserDefaults.standard.bool(forKey: "terminalCopyRemoveBoxDrawing"),
                        stripAnsiCodes: UserDefaults.standard.object(forKey: "terminalCopyStripAnsiCodes") as? Bool ?? true
                    )
                    string = TerminalTextCleaner.cleanText(string, settings: settings)

                    Clipboard.copy(string)
                    Ghostty.logger.debug("Wrote to clipboard: \(string.prefix(50))...")
                    return
                }
            }
        }

        static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
            // userdata is the GhosttyTerminalView instance
            guard let userdata = userdata else { return }
            let terminalView = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()

            Ghostty.logger.info("Close surface: processAlive=\(processAlive)")

            // Trigger process exit callback on main thread
            DispatchQueue.main.async {
                terminalView.onProcessExit?()
            }
        }
    }
}
