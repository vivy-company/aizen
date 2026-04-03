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

    func resizeSplit(_ node: SplitNode, to newRatio: CGFloat) {
        let updatedSplit = node.withUpdatedRatio(Double(newRatio))
        layout = layout.replacingNode(node, with: updatedSplit)
    }

    func equalize() {
        layout = layout.equalized()
    }

    func splitHorizontal() {
        splitRight()
    }

    func splitVertical() {
        splitDown()
    }

    func splitRight() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(paneId: sourcePaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitLeft() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(paneId: newPaneId),
            right: .leaf(paneId: sourcePaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitDown() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(paneId: sourcePaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitUp() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(paneId: newPaneId),
            right: .leaf(paneId: sourcePaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }


    static var sessionPersistenceEnabled: Bool {
        UserDefaults.standard.bool(forKey: "terminalSessionPersistence")
    }
}
