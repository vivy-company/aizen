//
//  GhosttyRenderingSetup.swift
//  aizen
//
//  Handles Metal layer setup and rendering configuration for Ghostty terminal
//

import AppKit
import GhosttyKit
import OSLog
import SwiftUI

/// Manages Metal rendering setup and configuration for Ghostty terminal
@MainActor
class GhosttyRenderingSetup {
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "GhosttyRendering")

    // MARK: - Terminal Settings from AppStorage

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"
    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    // MARK: - Surface Setup

    /// Create and configure the Ghostty surface
    func setupSurface(
        view: NSView,
        ghosttyApp: ghostty_app_t,
        worktreePath: String,
        initialBounds: NSRect,
        window: NSWindow?,
        paneId: String? = nil,
        command: String? = nil
    ) -> ghostty_surface_t? {
        // Configure surface with working directory
        var surfaceConfig = ghostty_surface_config_new()

        // CRITICAL: Set platform information
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()

        // Set userdata
        surfaceConfig.userdata = Unmanaged.passUnretained(view).toOpaque()

        // Set scale factor for retina displays
        surfaceConfig.scale_factor = Double(window?.backingScaleFactor ?? 2.0)

        // Set font size from Aizen settings
        surfaceConfig.font_size = Float(terminalFontSize)

        // Set working directory
        var workingDirPtr: UnsafeMutablePointer<CChar>?
        var initialInputPtr: UnsafeMutablePointer<CChar>?
        var commandPtr: UnsafeMutablePointer<CChar>?

        if let workingDir = strdup(worktreePath) {
            workingDirPtr = workingDir
            surfaceConfig.working_directory = UnsafePointer(workingDir)
        }

        // Check if session persistence is enabled and tmux is available
        var isRestoringTmuxSession = false
        if sessionPersistence, let paneId = paneId, TmuxSessionRuntime.shared.isTmuxAvailable() {
            // Check if we're restoring an existing tmux session
            isRestoringTmuxSession = TmuxSessionRuntime.shared.sessionExistsSync(paneId: paneId)

            // Use tmux for session persistence - set as the command directly
            // This makes tmux the shell process, not something running inside a shell
            let tmuxCommand = TmuxSessionRuntime.shared.attachOrCreateCommand(
                paneId: paneId,
                workingDirectory: worktreePath
            )
            if let cmd = strdup(tmuxCommand) {
                commandPtr = cmd
                surfaceConfig.command = UnsafePointer(cmd)
                Self.logger.info("Using tmux persistence for pane: \(paneId), restoring: \(isRestoringTmuxSession)")
            }
        }

        // Set initial_input if command provided (for presets)
        // Skip if we're restoring an existing tmux session - the command was already run before
        if let command = command, !command.isEmpty, !isRestoringTmuxSession {
            let inputWithNewline = command + "\n"
            if let input = strdup(inputWithNewline) {
                initialInputPtr = input
                surfaceConfig.initial_input = UnsafePointer(input)
                Self.logger.info("Setting initial_input for preset: \(command)")
            }
        }

        defer {
            if let wd = workingDirPtr {
                free(wd)
            }
            if let input = initialInputPtr {
                free(input)
            }
            if let cmd = commandPtr {
                free(cmd)
            }
        }

        // Create the surface
        // NOTE: subprocess spawns during ghostty_surface_new, so size warnings may appear
        // if view frame isn't set yet - this is unavoidable with current API
        guard let cSurface = ghostty_surface_new(ghosttyApp, &surfaceConfig) else {
            Self.logger.error("ghostty_surface_new failed")
            return nil
        }

        // Immediately set size after creation to minimize "small grid" warnings
        let scaledSize = view.convertToBacking(initialBounds.size.width > 0 ? initialBounds.size : NSSize(width: 800, height: 600))
        ghostty_surface_set_size(
            cSurface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )

        // Set content scale for retina displays
        let scale = window?.backingScaleFactor ?? 1.0
        ghostty_surface_set_content_scale(cSurface, scale, scale)

        Self.logger.info("Ghostty surface created at: \(worktreePath)")

        return cSurface
    }
}
