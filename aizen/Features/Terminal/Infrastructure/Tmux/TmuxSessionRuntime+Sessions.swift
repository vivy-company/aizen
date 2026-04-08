//
//  TmuxSessionRuntime+Sessions.swift
//  aizen
//
//  Session lifecycle operations for tmux-backed terminal persistence.
//

import Foundation
import OSLog

extension TmuxSessionRuntime {
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
}
