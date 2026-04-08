import Foundation

extension Notification.Name {
    /// Posted when the terminal scrollbar state changes.
    /// userInfo contains ScrollbarKey with Ghostty.Action.Scrollbar value.
    static let ghosttyDidUpdateScrollbar = Notification.Name("win.aizen.app.ghostty.didUpdateScrollbar")

    /// Posted when a Ghostty terminal search overlay should move keyboard focus to its field.
    static let ghosttySearchFocus = Notification.Name("win.aizen.app.ghostty.searchFocus")

    static let ghosttyConfigDidChange = Notification.Name("win.aizen.app.ghostty.configDidChange")
    static let ghosttyColorDidChange = Notification.Name("win.aizen.app.ghostty.colorDidChange")
    static let ghosttyBellDidRing = Notification.Name("win.aizen.app.ghostty.bellDidRing")
    static let ghosttyDidChangeReadonly = Notification.Name("win.aizen.app.ghostty.readonlyDidChange")

    static let ScrollbarKey = ghosttyDidUpdateScrollbar.rawValue + ".scrollbar"
    static let GhosttyConfigChangeKey = ghosttyConfigDidChange.rawValue
    static let GhosttyColorChangeKey = ghosttyColorDidChange.rawValue
    static let ReadonlyKey = ghosttyDidChangeReadonly.rawValue + ".readonly"
}

extension Ghostty {
    static let userNotificationCategory = "win.aizen.app.userNotification"
}

extension Ghostty.Notification {
    static let didUpdateRendererHealth = Notification.Name("win.aizen.app.ghostty.didUpdateRendererHealth")
    static let didContinueKeySequence = Notification.Name("win.aizen.app.ghostty.didContinueKeySequence")
    static let didEndKeySequence = Notification.Name("win.aizen.app.ghostty.didEndKeySequence")
    static let KeySequenceKey = didContinueKeySequence.rawValue + ".key"
    static let didChangeKeyTable = Notification.Name("win.aizen.app.ghostty.didChangeKeyTable")
    static let KeyTableKey = didChangeKeyTable.rawValue + ".action"
}
