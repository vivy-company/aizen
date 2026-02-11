//
//  TerminalSessionManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

struct TerminalRuntimeCounts {
    let livePanes: Int
    let runningPanes: Int
}

class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private var terminals: [String: GhosttyTerminalView] = [:]
    private var scrollViews: [String: TerminalScrollView] = [:]
    private var accessOrder: [String] = []
    private let maxTerminals = 50

    private init() {}

    private func key(for sessionId: UUID, paneId: String) -> String {
        "\(sessionId.uuidString)-\(paneId)"
    }

    private func keyPrefix(for sessionId: UUID) -> String {
        "\(sessionId.uuidString)-"
    }

    func getTerminal(for sessionId: UUID, paneId: String) -> GhosttyTerminalView? {
        let key = key(for: sessionId, paneId: paneId)
        if let terminal = terminals[key] {
            touch(key)
            return terminal
        }
        return nil
    }

    func setTerminal(_ terminal: GhosttyTerminalView, for sessionId: UUID, paneId: String) {
        let key = key(for: sessionId, paneId: paneId)
        terminals[key] = terminal
        touch(key)
        evictIfNeeded()
    }

    func removeTerminal(for sessionId: UUID, paneId: String) {
        let key = key(for: sessionId, paneId: paneId)
        if let terminal = terminals.removeValue(forKey: key) {
            cleanupTerminal(terminal)
        }
        scrollViews.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    func removeAllTerminals(for sessionId: UUID) {
        let prefix = keyPrefix(for: sessionId)
        for (key, terminal) in terminals where key.hasPrefix(prefix) {
            cleanupTerminal(terminal)
            terminals.removeValue(forKey: key)
        }
        scrollViews = scrollViews.filter { !$0.key.hasPrefix(prefix) }
        accessOrder.removeAll { $0.hasPrefix(prefix) }
    }

    // MARK: - Scroll View Management

    func getScrollView(for sessionId: UUID, paneId: String) -> TerminalScrollView? {
        let key = key(for: sessionId, paneId: paneId)
        if let scrollView = scrollViews[key] {
            touch(key)
            return scrollView
        }
        return nil
    }

    func setScrollView(_ scrollView: TerminalScrollView, for sessionId: UUID, paneId: String) {
        let key = key(for: sessionId, paneId: paneId)
        scrollViews[key] = scrollView
        touch(key)
        evictIfNeeded()
    }

    func getTerminalCount(for sessionId: UUID) -> Int {
        let prefix = keyPrefix(for: sessionId)
        return terminals.keys.filter { $0.hasPrefix(prefix) }.count
    }

    @MainActor
    func paneIds(for sessionId: UUID) -> [String] {
        let prefix = keyPrefix(for: sessionId)
        return terminals.keys
            .filter { $0.hasPrefix(prefix) }
            .map { key in
                String(key.dropFirst(prefix.count))
            }
    }

    @MainActor
    func runtimeCounts(for sessionId: UUID, paneIds: [String]) -> TerminalRuntimeCounts {
        var livePanes = 0
        var runningPanes = 0

        for paneId in paneIds {
            guard let terminal = getTerminal(for: sessionId, paneId: paneId) else { continue }
            livePanes += 1
            if !terminal.processExited {
                runningPanes += 1
            }
        }

        return TerminalRuntimeCounts(livePanes: livePanes, runningPanes: runningPanes)
    }

    private func touch(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictIfNeeded() {
        while terminals.count > maxTerminals, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            if let terminal = terminals.removeValue(forKey: oldest) {
                cleanupTerminal(terminal)
            }
            scrollViews.removeValue(forKey: oldest)
        }
    }

    private func cleanupTerminal(_ terminal: GhosttyTerminalView) {
        terminal.onProcessExit = nil
        terminal.onTitleChange = nil
        terminal.onProgressReport = nil
        terminal.onReady = nil
    }

    /// Check if any terminal pane needs confirmation before closing
    @MainActor
    func hasRunningProcess(for sessionId: UUID, paneIds: [String]) -> Bool {
        for paneId in paneIds {
            if let terminal = getTerminal(for: sessionId, paneId: paneId),
               terminal.needsConfirmQuit {
                return true
            }
        }
        return false
    }

    /// Check if a specific pane needs confirmation before closing
    @MainActor
    func paneHasRunningProcess(for sessionId: UUID, paneId: String) -> Bool {
        if let terminal = getTerminal(for: sessionId, paneId: paneId) {
            return terminal.needsConfirmQuit
        }
        return false
    }
}
