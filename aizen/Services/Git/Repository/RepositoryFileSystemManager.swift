//
//  RepositoryFileSystemManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import AppKit

/// Manages file system operations for repositories and worktrees
@MainActor
class RepositoryFileSystemManager {

    // MARK: - File System Operations

    /// Opens the specified path in Finder
    /// - Parameter path: The file system path to open
    func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    /// Opens a Terminal window at the specified path
    /// - Parameter path: The directory path to open in Terminal
    func openInTerminal(_ path: String) {
        guard let bundleId = UserDefaults.standard.string(forKey: "defaultTerminalBundleId") else {
            // No preference set, use system default
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }

        // Use selected terminal app if configured
        if let terminal = AppDetector.shared.detectedApps.first(where: { $0.bundleIdentifier == bundleId }) {
            AppDetector.shared.openPath(path, with: terminal)
        } else {
            // Fallback to system default if configured app is not found
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    /// Opens the specified path in the configured editor
    /// - Parameter path: The directory or file path to open
    ///
    /// Uses the default editor from UserDefaults (key: "defaultEditor").
    /// Falls back to Finder if the editor command fails.
    func openInEditor(_ path: String) {
        let useCliEditor = UserDefaults.standard.bool(forKey: "useCliEditor")

        // Use CLI command if toggled on
        if useCliEditor {
            let editor = UserDefaults.standard.string(forKey: "defaultEditor") ?? "code"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = [editor, path]

            do {
                try task.run()
            } catch {
                // Fallback to Finder if editor command fails
                openInFinder(path)
            }
            return
        }

        guard let bundleId = UserDefaults.standard.string(forKey: "defaultEditorBundleId") else {
            // No preference set, use system default
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }

        // Use selected editor app if configured
        if let editor = AppDetector.shared.detectedApps.first(where: { $0.bundleIdentifier == bundleId }) {
            AppDetector.shared.openPath(path, with: editor)
        } else {
            // Fallback to system default if configured app is not found
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}
