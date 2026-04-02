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

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "TmuxSessionRuntime")

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

    // MARK: - Session Management

    /// Create a new detached tmux session with status bar hidden
    func createSession(paneId: String, workingDirectory: String) async throws {
        guard let tmux = TmuxSessionSupport.tmuxPath() else {
            throw TmuxError.notInstalled
        }

        let sessionName = TmuxSessionSupport.sessionName(for: paneId)

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
        guard let tmux = TmuxSessionSupport.tmuxPath() else {
            return false
        }

        let sessionName = TmuxSessionSupport.sessionName(for: paneId)

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
        guard let tmux = TmuxSessionSupport.tmuxPath() else {
            return
        }

        let sessionName = TmuxSessionSupport.sessionName(for: paneId)

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
        guard let tmux = TmuxSessionSupport.tmuxPath() else {
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

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return output
                .components(separatedBy: .newlines)
                .filter { $0.hasPrefix(TmuxSessionSupport.sessionPrefix) }
        } catch {
            return []
        }
    }

    /// Kill all aizen-prefixed tmux sessions
    func killAllAizenSessions() async {
        let sessions = await listAizenSessions()
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                let paneId = String(session.dropFirst(TmuxSessionSupport.sessionPrefix.count))
                group.addTask {
                    await self.killSession(paneId: paneId)
                }
            }
        }
        Self.logger.info("Killed all aizen tmux sessions")
    }

    /// Clean up orphaned sessions (sessions without matching Core Data panes)
    func cleanupOrphanedSessions(validPaneIds: Set<String>) async {
        let sessions = await listAizenSessions()
        let orphanedSessions = sessions.filter { session in
            let paneId = String(session.dropFirst(TmuxSessionSupport.sessionPrefix.count))
            return !validPaneIds.contains(paneId)
        }

        await withTaskGroup(of: Void.self) { group in
            for session in orphanedSessions {
                let paneId = String(session.dropFirst(TmuxSessionSupport.sessionPrefix.count))
                group.addTask {
                    await self.killSession(paneId: paneId)
                    Self.logger.info("Cleaned up orphaned tmux session: \(session)")
                }
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
