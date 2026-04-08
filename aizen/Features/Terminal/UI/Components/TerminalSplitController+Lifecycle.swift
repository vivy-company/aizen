//
//  TerminalSplitController+Lifecycle.swift
//  aizen
//
//  Controller activation, focus, and keyboard monitoring.
//

import AppKit

@MainActor
extension TerminalSplitController {
    func handleAppear() {
        seedSessionLayoutIfNeeded()
        ensureKeyMonitor()

        guard isSelected else { return }
        activateSplitActions()
        syncGhosttySurfaceFocus()
        persistLayout()
        persistFocus()
        applyTitleForFocusedPane()
        focusRequestVersion += 1
    }

    func handleDisappear() {
        layoutSaveTask?.cancel()
        focusSaveTask?.cancel()
        contextSaveTask?.cancel()
        deactivateSplitActions()
        clearGhosttySurfaceFocus()

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func handleSelectionChange(_ selected: Bool) {
        isSelected = selected

        if selected {
            activateSplitActions()
            syncGhosttySurfaceFocus()
            persistLayout()
            persistFocus()
            applyTitleForFocusedPane()
            focusRequestVersion += 1
        } else {
            deactivateSplitActions()
            clearGhosttySurfaceFocus()
        }
    }

    func handlePaneFocus(_ paneId: String) {
        guard !isClosingSession else { return }
        guard layout.allPaneIds().contains(paneId) else { return }
        activateSplitActions()
        focusedPaneId = paneId
    }

    func handleVoiceRecordingChanged(for paneId: String, isRecording: Bool) {
        paneVoiceRecordingStates[paneId] = isRecording
        if focusedPaneId == paneId {
            focusedPaneVoiceRecording = isRecording
        }
    }

    func activateSplitActions() {
        TerminalSplitActionRouter.shared.activate(splitActions)
    }

    func deactivateSplitActions() {
        TerminalSplitActionRouter.shared.clear(splitActions)
    }

    func applyTitleForFocusedPane() {
        guard !isClosingSession, !session.isDeleted else { return }
        guard let sessionId = session.id else { return }

        if let title = paneTitles[focusedPaneId] {
            titleRegistry.setLiveTitle(title, for: sessionId)
        } else {
            titleRegistry.clearLiveTitle(for: sessionId)
        }
    }
}
