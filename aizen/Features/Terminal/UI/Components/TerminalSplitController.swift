//
//  TerminalSplitController.swift
//  aizen
//
//  Controller-owned split state aligned with Ghostty's terminal controller model.
//

import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class TerminalSplitController: ObservableObject {
    enum CloseAction {
        case pane
        case tab
    }

    let worktree: Worktree
    let session: TerminalSession
    let sessionManager: TerminalRuntimeStore
    let splitActions = TerminalSplitActions()
    let titleRegistry = TerminalTitleRegistry.shared

    @Published var layout: SplitNode {
        didSet {
            guard isSelected else { return }
            scheduleLayoutSave()
        }
    }

    @Published var focusedPaneId: String {
        didSet {
            guard isSelected else { return }
            guard !focusedPaneId.isEmpty else { return }
            focusedPaneVoiceRecording = paneVoiceRecordingStates[focusedPaneId] ?? false
            syncGhosttySurfaceFocus()
            scheduleFocusSave()
            applyTitleForFocusedPane()
        }
    }

    @Published var showCloseConfirmation = false
    @Published var voiceAction: (paneId: String, action: VoiceAction)?
    @Published var focusRequestVersion = 0

    var isSelected: Bool
    var paneTitles: [String: String] = [:]
    var layoutSaveTask: Task<Void, Never>?
    var focusSaveTask: Task<Void, Never>?
    var contextSaveTask: Task<Void, Never>?
    var pendingCloseAction: CloseAction = .pane
    var keyMonitor: Any?
    var focusedPaneVoiceRecording = false
    var paneVoiceRecordingStates: [String: Bool] = [:]
    var closingPaneIds: Set<String> = []
    var isClosingSession = false

    init(
        worktree: Worktree,
        session: TerminalSession,
        sessionManager: TerminalRuntimeStore,
        isSelected: Bool
    ) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.isSelected = isSelected

        if let layoutJSON = session.splitLayout,
           let decoded = SplitLayoutHelper.decode(layoutJSON) {
            self.layout = decoded
            self.focusedPaneId = session.focusedPaneId ?? decoded.allPaneIds().first ?? ""
        } else {
            let defaultPaneId = TerminalLayoutDefaults.paneId(
                sessionId: session.id,
                focusedPaneId: session.focusedPaneId
            )
            self.layout = SplitLayoutHelper.createDefault(paneId: defaultPaneId)
            self.focusedPaneId = defaultPaneId
        }

        splitActions.configure(
            splitRight: { [weak self] in self?.splitRight() },
            splitLeft: { [weak self] in self?.splitLeft() },
            splitDown: { [weak self] in self?.splitDown() },
            splitUp: { [weak self] in self?.splitUp() },
            closePane: { [weak self] in self?.closePane() }
        )
    }

    func handleTitleChange(for paneId: String, title: String) {
        paneTitles[paneId] = title
        if paneId == focusedPaneId,
           let sessionId = session.id {
            titleRegistry.setLiveTitle(title, for: sessionId)
        }
    }

    static var sessionPersistenceEnabled: Bool {
        UserDefaults.standard.bool(forKey: "terminalSessionPersistence")
    }
}
