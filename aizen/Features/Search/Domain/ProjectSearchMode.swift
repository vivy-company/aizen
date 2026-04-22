import Foundation

nonisolated enum ProjectSearchMode: String, CaseIterable, Identifiable, Sendable {
    case files
    case content

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files:
            "Files"
        case .content:
            "Content"
        }
    }

    var placeholder: String {
        switch self {
        case .files:
            "Search files…"
        case .content:
            "Search file contents…"
        }
    }

    var keyboardShortcutLabel: String {
        switch self {
        case .files:
            "⌘P"
        case .content:
            "⌘⇧F"
        }
    }

    func toggled() -> ProjectSearchMode {
        switch self {
        case .files:
            .content
        case .content:
            .files
        }
    }
}

nonisolated enum ProjectSearchGrepMode: String, CaseIterable, Identifiable, Sendable {
    case plain
    case regex
    case fuzzy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain:
            "Plain"
        case .regex:
            "Regex"
        case .fuzzy:
            "Fuzzy"
        }
    }

    var fffModeValue: UInt8 {
        switch self {
        case .plain:
            0
        case .regex:
            1
        case .fuzzy:
            2
        }
    }
}
