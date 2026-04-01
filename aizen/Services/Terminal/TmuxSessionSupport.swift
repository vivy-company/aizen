//
//  TmuxSessionSupport.swift
//  aizen
//
//  Pure helpers for tmux executable discovery, config generation, and command building.
//

import Foundation

enum TmuxSessionSupport {
    static let sessionPrefix = "aizen-"

    private static let candidatePaths = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux"
    ]

    static var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aizen")
            .appendingPathComponent("tmux.conf")
    }

    static func isTmuxAvailable() -> Bool {
        candidatePaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func tmuxPath() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func sessionName(for paneId: String) -> String {
        sessionPrefix + paneId
    }

    static func configContents(themeName: String, modeStyle: String) -> String {
        """
        # Aizen tmux configuration
        # This file is auto-generated - changes will be overwritten

        # Enable hyperlinks (OSC 8)
        set -as terminal-features ",*:hyperlinks"

        # Allow OSC sequences to pass through (title updates, etc.)
        set -g allow-passthrough on

        # Hide status bar
        set -g status off

        # Increase scrollback buffer (default is 2000)
        set -g history-limit 10000

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
    }

    static func attachOrCreateCommand(
        paneId: String,
        workingDirectory: String,
        tmuxPath: String?
    ) -> String {
        guard let tmuxPath else { return "" }

        let sessionName = sessionName(for: paneId)
        let escapedDir = workingDirectory.replacingOccurrences(of: "'", with: "'\\''")
        return "\(tmuxPath) -f '\(configFileURL.path)' new-session -A -s \(sessionName) -c '\(escapedDir)'"
    }
}
