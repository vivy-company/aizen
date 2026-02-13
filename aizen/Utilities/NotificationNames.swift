//
//  NotificationNames.swift
//  aizen
//
//  Centralized notification names for app-wide events
//

import Foundation

extension Notification.Name {
    // MARK: - Chat View Lifecycle

    /// Posted when chat view appears and becomes active
    static let chatViewDidAppear = Notification.Name("ChatViewDidAppear")

    /// Posted when chat view disappears and becomes inactive
    static let chatViewDidDisappear = Notification.Name("ChatViewDidDisappear")

    // MARK: - Keyboard Shortcuts

    /// Posted when Shift+Tab is pressed to cycle through available modes
    static let cycleModeShortcut = Notification.Name("CycleModeShortcut")

    /// Posted when Escape is pressed to interrupt the current agent operation
    static let interruptAgentShortcut = Notification.Name("InterruptAgentShortcut")

    /// Posted when Command+P is pressed to open file search
    static let fileSearchShortcut = Notification.Name("FileSearchShortcut")

    /// Posted when Command+K is pressed to open command palette
    static let commandPaletteShortcut = Notification.Name("CommandPaletteShortcut")

    /// Posted when Command+Shift+K is pressed to quick-switch to previous worktree
    static let quickSwitchWorktree = Notification.Name("QuickSwitchWorktree")

    // MARK: - Navigation

    /// Posted when navigating to a specific worktree from command palette
    static let navigateToWorktree = Notification.Name("NavigateToWorktree")

    /// Posted when switching to a specific tab in a specific worktree
    static let switchToWorktreeTab = Notification.Name("SwitchToWorktreeTab")

    /// Posted when switching to a specific terminal session in a specific worktree
    static let switchToTerminalSession = Notification.Name("SwitchToTerminalSession")

    /// Posted when switching to a specific browser session in a specific worktree
    static let switchToBrowserSession = Notification.Name("SwitchToBrowserSession")

    // MARK: - File Operations

    /// Posted when a file should be opened in the editor (from tool calls, etc.)
    static let openFileInEditor = Notification.Name("OpenFileInEditor")

    // MARK: - Agent Streaming

    /// Posted when agent streaming starts for a worktree (userInfo: ["worktreePath": String])
    static let agentStreamingDidStart = Notification.Name("AgentStreamingDidStart")

    /// Posted when agent streaming stops for a worktree (userInfo: ["worktreePath": String])
    static let agentStreamingDidStop = Notification.Name("AgentStreamingDidStop")

    // MARK: - Settings

    /// Posted when the Settings view should open the Pro tab
    static let openSettingsPro = Notification.Name("OpenSettingsPro")

    /// Posted when a license deep link is received (token + auto-activate)
    static let openLicenseDeepLink = Notification.Name("OpenLicenseDeepLink")
}
