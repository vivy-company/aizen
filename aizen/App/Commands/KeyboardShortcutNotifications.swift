import Foundation

enum ProjectSearchShortcutUserInfoKey {
    static let mode = "mode"
}

extension Notification.Name {
    static let cycleModeShortcut = Notification.Name("CycleModeShortcut")
    static let interruptAgentShortcut = Notification.Name("InterruptAgentShortcut")
    static let projectSearchShortcut = Notification.Name("ProjectSearchShortcut")
    static let commandPaletteShortcut = Notification.Name("CommandPaletteShortcut")
    static let quickSwitchWorktree = Notification.Name("QuickSwitchWorktree")
}
