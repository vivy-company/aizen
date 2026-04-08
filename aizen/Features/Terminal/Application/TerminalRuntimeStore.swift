//
//  TerminalRuntimeStore.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import AppKit
import Foundation

struct TerminalRuntimeCounts {
    let livePanes: Int
    let runningPanes: Int
}

class TerminalRuntimeStore {
    static let shared = TerminalRuntimeStore()

    var terminals: [String: AizenTerminalSurfaceView] = [:]
    var accessOrder: [String] = []
    let maxTerminals = 50

    private init() {}

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

    @MainActor
    func focusedPaneId(for sessionId: UUID) -> String? {
        let prefix = keyPrefix(for: sessionId)

        for (key, terminal) in terminals where key.hasPrefix(prefix) {
            guard terminal.window?.firstResponder === terminal else { continue }
            return String(key.dropFirst(prefix.count))
        }

        return nil
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
