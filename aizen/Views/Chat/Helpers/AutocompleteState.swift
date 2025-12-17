//
//  AutocompleteState.swift
//  aizen
//
//  State model for unified autocomplete system
//

import Foundation
import AppKit

// MARK: - Trigger Types

enum AutocompleteTrigger: Equatable {
    case file(query: String)
    case command(query: String)

    var query: String {
        switch self {
        case .file(let query), .command(let query):
            return query
        }
    }
}

// MARK: - Autocomplete Item

enum AutocompleteItem: Identifiable, Equatable {
    case file(FileSearchIndexResult)
    case command(AvailableCommand)

    var id: String {
        switch self {
        case .file(let result):
            return "file:\(result.path)"
        case .command(let cmd):
            return "cmd:\(cmd.name)"
        }
    }

    var displayName: String {
        switch self {
        case .file(let result):
            return (result.relativePath as NSString).lastPathComponent
        case .command(let cmd):
            return "/\(cmd.name)"
        }
    }

    var detail: String {
        switch self {
        case .file(let result):
            let path = result.relativePath as NSString
            let dir = path.deletingLastPathComponent
            return dir.isEmpty ? "" : dir
        case .command(let cmd):
            return cmd.description
        }
    }

    static func == (lhs: AutocompleteItem, rhs: AutocompleteItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Navigation Actions

enum AutocompleteNavigationAction {
    case up
    case down
    case select
    case dismiss
}

// MARK: - Autocomplete State

struct AutocompleteState {
    var isActive: Bool = false
    var trigger: AutocompleteTrigger?
    var items: [AutocompleteItem] = []
    var selectedIndex: Int = 0
    var triggerRange: NSRange?
    var cursorRect: NSRect = .zero

    var selectedItem: AutocompleteItem? {
        guard selectedIndex >= 0, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    mutating func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = min(items.count - 1, selectedIndex + 1)
    }

    mutating func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    mutating func reset() {
        isActive = false
        trigger = nil
        items = []
        selectedIndex = 0
        triggerRange = nil
        cursorRect = .zero
    }
}
