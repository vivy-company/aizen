//
//  TmuxSessionRuntime.swift
//  aizen
//
//  Manages tmux sessions for terminal persistence across app restarts
//

import Foundation
import OSLog

/// Actor that manages tmux sessions for terminal persistence
///
/// When terminal session persistence is enabled, each terminal pane runs inside
/// a hidden tmux session. This allows terminals to survive app restarts.
actor TmuxSessionRuntime {
    static let shared = TmuxSessionRuntime()

    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "TmuxSessionRuntime")

    private init() {
        Task { await ensureConfigExists() }
    }

    /// Update tmux config when theme changes
    func updateConfig() {
        ensureConfigExists()
    }

    /// Ensure tmux config exists in ~/.aizen/tmux.conf
    private func ensureConfigExists() {
        let configFile = TmuxSessionSupport.configFileURL

        // Create ~/.aizen if needed
        try? FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Get theme-based mode style for selection highlighting
        let themeName = UserDefaults.standard.string(forKey: "terminalThemeName") ?? "Aizen Dark"
        let modeStyle = GhosttyThemeParser.loadTmuxModeStyle(named: themeName)
        let config = TmuxSessionSupport.configContents(themeName: themeName, modeStyle: modeStyle)

        try? config.write(to: configFile, atomically: true, encoding: .utf8)
    }

    // MARK: - tmux Availability

    /// Check if tmux is installed and available
    nonisolated func isTmuxAvailable() -> Bool {
        TmuxSessionSupport.isTmuxAvailable()
    }

    /// Get the path to tmux executable
    nonisolated func tmuxPath() -> String? {
        TmuxSessionSupport.tmuxPath()
    }

    // MARK: - Command Generation

    /// Generate the tmux command to attach or create a session
    ///
    /// Uses `tmux new-session -A` which attaches to existing session or creates new one.
    /// Command is executed directly by Ghostty (not through a shell), so it's shell-agnostic.
    /// The user's configured shell runs inside the tmux session.
    nonisolated func attachOrCreateCommand(paneId: String, workingDirectory: String) -> String {
        TmuxSessionSupport.attachOrCreateCommand(
            paneId: paneId,
            workingDirectory: workingDirectory,
            tmuxPath: TmuxSessionSupport.tmuxPath()
        )
    }
}

// MARK: - Errors

enum TmuxError: Error, LocalizedError {
    case notInstalled
    case sessionCreationFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "tmux is not installed"
        case .sessionCreationFailed:
            return "Failed to create tmux session"
        }
    }
}
