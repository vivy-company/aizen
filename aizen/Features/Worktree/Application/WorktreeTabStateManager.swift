//
//  WorktreeTabStateManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Combine
import SwiftUI

// MARK: - WorktreeTabState

struct WorktreeTabState: Codable {
    var viewType: String
    var chatSessionId: UUID?
    var terminalSessionId: UUID?
    var browserSessionId: UUID?
    var fileSessionId: UUID?

    init(viewType: String = "chat",
         chatSessionId: UUID? = nil,
         terminalSessionId: UUID? = nil,
         browserSessionId: UUID? = nil,
         fileSessionId: UUID? = nil) {
        self.viewType = viewType
        self.chatSessionId = chatSessionId
        self.terminalSessionId = terminalSessionId
        self.browserSessionId = browserSessionId
        self.fileSessionId = fileSessionId
    }
}

// MARK: - WorktreeTabStateManager

class WorktreeTabStateManager: ObservableObject {
    @Published private var tabStates: [String: WorktreeTabState] = [:]
    @AppStorage("worktreeTabStates") private var tabStatesData: String = "{}"

    init() {
        loadAllStates()
    }

    // MARK: - Load/Save

    private func loadAllStates() {
        guard let data = tabStatesData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: WorktreeTabState].self, from: data) else {
            return
        }
        tabStates = decoded
    }

    private func saveAllStates() {
        guard let encoded = try? JSONEncoder().encode(tabStates),
              let jsonString = String(data: encoded, encoding: .utf8) else {
            return
        }
        tabStatesData = jsonString
    }

    // MARK: - Public API

    func getState(for worktreeId: UUID) -> WorktreeTabState {
        return tabStates[worktreeId.uuidString] ?? WorktreeTabState()
    }

    func saveViewType(_ viewType: String, for worktreeId: UUID) {
        var state = getState(for: worktreeId)
        state.viewType = viewType
        tabStates[worktreeId.uuidString] = state
        saveAllStates()
        objectWillChange.send()
    }

    func saveSessionId(_ sessionId: UUID?, for viewType: String, worktreeId: UUID) {
        var state = getState(for: worktreeId)

        switch viewType {
        case "chat":
            state.chatSessionId = sessionId
        case "terminal":
            state.terminalSessionId = sessionId
        case "browser":
            state.browserSessionId = sessionId
        case "files":
            state.fileSessionId = sessionId
        default:
            break
        }

        tabStates[worktreeId.uuidString] = state
        saveAllStates()
        objectWillChange.send()
    }

    func getSessionId(for viewType: String, worktreeId: UUID) -> UUID? {
        let state = getState(for: worktreeId)

        switch viewType {
        case "chat":
            return state.chatSessionId
        case "terminal":
            return state.terminalSessionId
        case "browser":
            return state.browserSessionId
        case "files":
            return state.fileSessionId
        default:
            return nil
        }
    }

    func hasStoredState(for worktreeId: UUID) -> Bool {
        return tabStates[worktreeId.uuidString] != nil
    }
}
