//
//  RepositoryFileSystemManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import AppKit

/// Manages file system operations for repositories and worktrees
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
        let script = """
        tell application "Terminal"
            do script "cd '\(path)'"
            activate
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Opens the specified path in the configured editor
    /// - Parameter path: The directory or file path to open
    ///
    /// Uses the default editor from UserDefaults (key: "defaultEditor").
    /// Falls back to Finder if the editor command fails.
    func openInEditor(_ path: String) {
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
    }
}
