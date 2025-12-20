//
//  TmuxSessionManager.swift
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
actor TmuxSessionManager {
    static let shared = TmuxSessionManager()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "TmuxSessionManager")
    private let sessionPrefix = "aizen-"

    private let configPath: String = {
        let aizenDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aizen")
        let configFile = aizenDir.appendingPathComponent("tmux.conf")
        return configFile.path
    }()

    private init() {
        Task { await ensureConfigExists() }
    }

    /// Update tmux config when theme changes
    func updateConfig() {
        ensureConfigExists()
    }

    /// Ensure tmux config exists in ~/.aizen/tmux.conf
    private func ensureConfigExists() {
        let aizenDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aizen")

        // Create ~/.aizen if needed
        try? FileManager.default.createDirectory(at: aizenDir, withIntermediateDirectories: true)

        let configFile = aizenDir.appendingPathComponent("tmux.conf")

        // Get theme-based mode style for selection highlighting
        let themeName = UserDefaults.standard.string(forKey: "terminalThemeName") ?? "Catppuccin Mocha"
        let modeStyle = GhosttyThemeParser.loadTmuxModeStyle(named: themeName)

        // Always overwrite to ensure latest config
        let config = """
        # Aizen tmux configuration
        # This file is auto-generated - changes will be overwritten

        # Enable hyperlinks (OSC 8)
        set -as terminal-features ",*:hyperlinks"

        # Allow OSC sequences to pass through (title updates, etc.)
        set -g allow-passthrough on

        # Hide status bar
        set -g status off

        # Increase scrollback buffer (default is 2000)
        set -g history-limit 500000

        # Enable mouse support
        set -g mouse on

        # Set default terminal with true color support
        set -g default-terminal "xterm-256color"
        set -ag terminal-overrides ",xterm-256color:RGB"

        # Selection highlighting in copy-mode (from theme: \(themeName))
        set -g mode-style "\(modeStyle)"

        # Smart mouse scroll: copy-mode at shell, passthrough in TUI apps
        bind -n WheelUpPane if -F '#{||:#{mouse_any_flag},#{alternate_on}}' 'send-keys -M' 'copy-mode -eH; send-keys -M'
        bind -n WheelDownPane if -F '#{||:#{mouse_any_flag},#{alternate_on}}' 'send-keys -M' 'send-keys -M'
        """

        try? config.write(to: configFile, atomically: true, encoding: .utf8)
    }

    // MARK: - tmux Availability

    /// Check if tmux is installed and available
    nonisolated func isTmuxAvailable() -> Bool {
        let paths = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Get the path to tmux executable
    nonisolated func tmuxPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Session Management

    /// Create a new detached tmux session with status bar hidden
    func createSession(paneId: String, workingDirectory: String) async throws {
        guard let tmux = tmuxPath() else {
            throw TmuxError.notInstalled
        }

        let sessionName = sessionPrefix + paneId

        // Create detached session with working directory and disable status bar
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = [
            "new-session",
            "-d",
            "-s", sessionName,
            "-c", workingDirectory
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TmuxError.sessionCreationFailed
        }

        // Disable status bar for this session
        let setStatusProcess = Process()
        setStatusProcess.executableURL = URL(fileURLWithPath: tmux)
        setStatusProcess.arguments = [
            "set-option",
            "-t", sessionName,
            "status", "off"
        ]

        try setStatusProcess.run()
        setStatusProcess.waitUntilExit()

        Self.logger.info("Created tmux session: \(sessionName)")
    }

    /// Check if a tmux session exists for the given pane ID
    func sessionExists(paneId: String) async -> Bool {
        sessionExistsSync(paneId: paneId)
    }

    /// Synchronous check if a tmux session exists for the given pane ID
    /// Use this when you need to check from non-async context
    nonisolated func sessionExistsSync(paneId: String) -> Bool {
        guard let tmux = tmuxPath() else {
            return false
        }

        let sessionName = sessionPrefix + paneId

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = ["has-session", "-t", sessionName]

        // Suppress stderr (tmux outputs "session not found" to stderr)
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Kill a specific tmux session
    func killSession(paneId: String) async {
        guard let tmux = tmuxPath() else {
            return
        }

        let sessionName = sessionPrefix + paneId

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = ["kill-session", "-t", sessionName]
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            Self.logger.info("Killed tmux session: \(sessionName)")
        } catch {
            Self.logger.error("Failed to kill tmux session: \(sessionName)")
        }
    }

    /// List all aizen-prefixed tmux sessions
    func listAizenSessions() async -> [String] {
        guard let tmux = tmuxPath() else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = ["list-sessions", "-F", "#{session_name}"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return output
                .components(separatedBy: .newlines)
                .filter { $0.hasPrefix(sessionPrefix) }
        } catch {
            return []
        }
    }

    /// Kill all aizen-prefixed tmux sessions
    func killAllAizenSessions() async {
        let sessions = await listAizenSessions()
        for session in sessions {
            let paneId = String(session.dropFirst(sessionPrefix.count))
            await killSession(paneId: paneId)
        }
        Self.logger.info("Killed all aizen tmux sessions")
    }

    /// Clean up orphaned sessions (sessions without matching Core Data panes)
    func cleanupOrphanedSessions(validPaneIds: Set<String>) async {
        let sessions = await listAizenSessions()

        for session in sessions {
            let paneId = String(session.dropFirst(sessionPrefix.count))
            if !validPaneIds.contains(paneId) {
                await killSession(paneId: paneId)
                Self.logger.info("Cleaned up orphaned tmux session: \(session)")
            }
        }
    }

    // MARK: - Command Generation

    /// Generate the tmux command to attach or create a session
    ///
    /// Uses `tmux new-session -A` which attaches to existing session or creates new one.
    /// Command is executed directly by Ghostty (not through a shell), so it's shell-agnostic.
    /// The user's configured shell runs inside the tmux session.
    nonisolated func attachOrCreateCommand(paneId: String, workingDirectory: String) -> String {
        guard let tmux = tmuxPath() else {
            // Fallback to default shell if tmux not available
            return ""
        }

        let sessionName = sessionPrefix + paneId
        let escapedDir = workingDirectory.replacingOccurrences(of: "'", with: "'\\''")

        return "\(tmux) -f '\(configPath)' new-session -A -s \(sessionName) -c '\(escapedDir)'"
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
