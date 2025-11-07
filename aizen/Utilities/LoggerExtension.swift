//
//  LoggerExtension.swift
//  aizen
//
//  Unified logging utility for the application
//

import Foundation
import os.log

extension Logger {
    /// Create a logger for a specific category
    nonisolated static func forCategory(_ category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: category)
    }

    /// Convenience logger instances for common categories
    static let agent = Logger.forCategory("Agent")
    static let git = Logger.forCategory("Git")
    static let terminal = Logger.forCategory("Terminal")
    static let chat = Logger.forCategory("Chat")
    static let workspace = Logger.forCategory("Workspace")
    static let worktree = Logger.forCategory("Worktree")
    static let settings = Logger.forCategory("Settings")
    static let audio = Logger.forCategory("Audio")
    static let acp = Logger.forCategory("ACP")
}
