import Foundation

enum TerminalPreferences {
    static let scrollbackLimitMBKey = "terminalScrollbackLimitMB"

    static let defaultScrollbackLimitMB = 5
    static let minScrollbackLimitMB = 1
    static let maxScrollbackLimitMB = 50

    static func clampedScrollbackLimitMB(_ value: Int) -> Int {
        min(max(value, minScrollbackLimitMB), maxScrollbackLimitMB)
    }

    static func scrollbackLimitBytes(fromMB value: Int) -> Int {
        clampedScrollbackLimitMB(value) * 1_000_000
    }
}
