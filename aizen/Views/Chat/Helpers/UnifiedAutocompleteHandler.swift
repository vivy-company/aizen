//
//  UnifiedAutocompleteHandler.swift
//  aizen
//
//  Unified handler for @ file mentions and / commands autocomplete
//

import SwiftUI
import Combine
import os.log

@MainActor
class UnifiedAutocompleteHandler: ObservableObject {
    @Published var state = AutocompleteState()

    private let logger = Logger.forCategory("Autocomplete")
    private let fileSearchService = FileSearchService.shared
    private var fileIndex: [FileSearchIndexResult] = []
    private var searchTask: Task<Void, Never>?
    private var isIndexing = false

    // Dependencies
    weak var agentSession: AgentSession?
    var worktreePath: String = ""

    // MARK: - Index Management

    func indexWorktree() async {
        guard !worktreePath.isEmpty, !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        do {
            fileIndex = try await fileSearchService.indexDirectory(worktreePath)
            logger.debug("Indexed \(self.fileIndex.count) files in worktree")
        } catch {
            logger.error("Failed to index worktree: \(error.localizedDescription)")
            fileIndex = []
        }
    }

    // MARK: - Trigger Detection

    func detectTrigger(in text: String, cursorPosition: Int) -> (trigger: AutocompleteTrigger, range: NSRange)? {
        guard cursorPosition > 0, cursorPosition <= text.count else { return nil }

        let textBeforeCursor = String(text.prefix(cursorPosition))

        var lastTriggerIndex: String.Index?
        var triggerChar: Character?

        // Scan backwards from cursor to find trigger
        for char in textBeforeCursor.reversed() {
            if char.isWhitespace || char.isNewline {
                break
            }

            if char == "@" || char == "/" {
                let distance = textBeforeCursor.distance(from: textBeforeCursor.startIndex, to: textBeforeCursor.endIndex) - 1
                var currentIndex = textBeforeCursor.index(textBeforeCursor.startIndex, offsetBy: distance)

                // Find actual position of trigger
                var tempIndex = textBeforeCursor.endIndex
                for (i, c) in textBeforeCursor.enumerated().reversed() {
                    if c == char {
                        tempIndex = textBeforeCursor.index(textBeforeCursor.startIndex, offsetBy: i)
                        break
                    }
                    if c.isWhitespace || c.isNewline {
                        break
                    }
                }

                if tempIndex != textBeforeCursor.endIndex {
                    lastTriggerIndex = tempIndex
                    triggerChar = char
                }
                break
            }
        }

        guard let triggerIndex = lastTriggerIndex,
              let char = triggerChar else { return nil }

        let triggerOffset = text.distance(from: text.startIndex, to: triggerIndex)

        // Validate: trigger must be at word boundary
        if triggerOffset > 0 {
            let prevIndex = text.index(text.startIndex, offsetBy: triggerOffset - 1)
            let prevChar = text[prevIndex]
            if !prevChar.isWhitespace && !prevChar.isNewline {
                return nil
            }
        }

        // Extract query
        let queryStartOffset = triggerOffset + 1
        let query: String
        if queryStartOffset < cursorPosition {
            let queryStart = text.index(text.startIndex, offsetBy: queryStartOffset)
            let queryEnd = text.index(text.startIndex, offsetBy: cursorPosition)
            query = String(text[queryStart..<queryEnd])
        } else {
            query = ""
        }

        let range = NSRange(location: triggerOffset, length: cursorPosition - triggerOffset)

        switch char {
        case "@":
            return (.file(query: query), range)
        case "/":
            // Commands only trigger at start or after newline
            let isAtStart = triggerOffset == 0
            let isAfterNewline = triggerOffset > 0 && text[text.index(text.startIndex, offsetBy: triggerOffset - 1)].isNewline
            if isAtStart || isAfterNewline {
                return (.command(query: query), range)
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Text Change Handling

    func handleTextChange(text: String, cursorPosition: Int, cursorRect: NSRect) {
        guard let (trigger, range) = detectTrigger(in: text, cursorPosition: cursorPosition) else {
            dismissAutocomplete()
            return
        }

        state.trigger = trigger
        state.triggerRange = range
        state.cursorRect = cursorRect
        state.isActive = true

        // Debounced search
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(for: trigger)
        }
    }

    private func performSearch(for trigger: AutocompleteTrigger) async {
        switch trigger {
        case .file(let query):
            let results = await fileSearchService.search(query: query, in: fileIndex, worktreePath: worktreePath)
            state.items = results.prefix(10).map { .file($0) }

        case .command(let query):
            let commands = agentSession?.availableCommands ?? []
            let filtered: [AvailableCommand]
            if query.isEmpty {
                filtered = Array(commands.prefix(10))
            } else {
                filtered = commands.filter {
                    $0.name.lowercased().hasPrefix(query.lowercased()) ||
                    $0.description.lowercased().contains(query.lowercased())
                }
            }
            state.items = filtered.prefix(10).map { .command($0) }
        }

        state.selectedIndex = 0
    }

    // MARK: - Navigation

    func navigateUp() -> Bool {
        guard state.isActive, !state.items.isEmpty else { return false }
        state.selectPrevious()
        return true
    }

    func navigateDown() -> Bool {
        guard state.isActive, !state.items.isEmpty else { return false }
        state.selectNext()
        return true
    }

    func selectCurrent() -> (replacement: String, range: NSRange)? {
        guard state.isActive,
              let item = state.selectedItem,
              let range = state.triggerRange else { return nil }

        let replacement: String
        switch item {
        case .file(let result):
            replacement = "@\(result.relativePath) "
        case .command(let command):
            replacement = "/\(command.name) "
        }

        dismissAutocomplete()
        return (replacement, range)
    }

    func dismissAutocomplete() {
        searchTask?.cancel()
        state.reset()
    }

    // MARK: - Direct Update

    func updateCursorRect(_ rect: NSRect) {
        state.cursorRect = rect
    }
}
