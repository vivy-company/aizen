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

    func activePaneId() -> String {
        let paneIds = layout.allPaneIds()
        if let sessionId = session.id,
           let responderPaneId = sessionManager.focusedPaneId(for: sessionId),
           paneIds.contains(responderPaneId) {
            if focusedPaneId != responderPaneId {
                focusedPaneId = responderPaneId
            }
            return responderPaneId
        }

        if paneIds.contains(focusedPaneId) {
            return focusedPaneId
        }

        if let fallbackPaneId = paneIds.first {
            focusedPaneId = fallbackPaneId
            return fallbackPaneId
        }

        return focusedPaneId
    }

    func transferFocus(from sourcePaneId: String, to targetPaneId: String?) {
        guard let targetPaneId else { return }

        if focusedPaneId != targetPaneId {
            focusedPaneId = targetPaneId
        }

        if let sessionId = session.id,
           let targetSurface = sessionManager.getTerminal(for: sessionId, paneId: targetPaneId) {
            let sourceSurface = sessionManager.getTerminal(for: sessionId, paneId: sourcePaneId)
            Ghostty.moveFocus(to: targetSurface, from: sourceSurface)
        }

        focusRequestVersion += 1
    }

    private func ensureKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleVoiceShortcut(event) ?? event
        }
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

    private func handleVoiceShortcut(_ event: NSEvent) -> NSEvent? {
        guard isSelected else { return event }
        let targetPaneId = activePaneId()

        if focusedPaneVoiceRecording {
            if event.keyCode == 53 {
                voiceAction = (targetPaneId, .cancel)
                return nil
            }
            if event.keyCode == 36 {
                voiceAction = (targetPaneId, .accept)
                return nil
            }
        }

        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.shift),
              event.charactersIgnoringModifiers?.lowercased() == "m" else {
            return event
        }

        voiceAction = (targetPaneId, .toggle)
        return nil
    }

    func syncGhosttySurfaceFocus() {
        guard isSelected, let sessionId = session.id else { return }

        let paneIds = Set(layout.allPaneIds())
        for paneId in paneIds {
            guard let surface = sessionManager.getTerminal(for: sessionId, paneId: paneId) else { continue }
            surface.setGhosttyFocused(paneId == focusedPaneId)
        }
    }

    func clearGhosttySurfaceFocus() {
        guard let sessionId = session.id else { return }

        let paneIds = Set(layout.allPaneIds())
        for paneId in paneIds {
            guard let surface = sessionManager.getTerminal(for: sessionId, paneId: paneId) else { continue }
            surface.setGhosttyFocused(false)
        }
    }
}
