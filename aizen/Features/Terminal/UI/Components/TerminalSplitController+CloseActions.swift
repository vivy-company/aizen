//
//  TerminalSplitController+CloseActions.swift
//  aizen
//
//  Pane and tab close / teardown flow
//

import Foundation
import CoreData
import os

extension TerminalSplitController {
    func handleProcessExit(for paneId: String) {
        guard !isClosingSession else { return }
        guard !closingPaneIds.contains(paneId) else { return }

        paneVoiceRecordingStates.removeValue(forKey: paneId)

        if let sessionId = session.id {
            sessionManager.removeTerminal(for: sessionId, paneId: paneId)
        }

        let paneIds = layout.allPaneIds()
        guard paneIds.contains(paneId) else { return }
        closingPaneIds.insert(paneId)
        let shouldTransferFocus = activePaneId() == paneId

        if paneIds.count == 1 {
            closeTab()
            return
        }

        if let newLayout = layout.removingPane(paneId) {
            if shouldTransferFocus {
                transferFocus(from: paneId, to: newLayout.allPaneIds().first)
            } else if focusedPaneId == paneId, let fallbackPaneId = newLayout.allPaneIds().first {
                focusedPaneId = fallbackPaneId
            }
            layout = newLayout
        }
    }

    func closePane() {
        let paneCount = layout.allPaneIds().count

        if paneCount == 1 {
            if let sessionId = session.id,
               sessionManager.paneHasRunningProcess(for: sessionId, paneId: focusedPaneId) {
                pendingCloseAction = .tab
                showCloseConfirmation = true
            } else {
                closeTab()
            }
        } else {
            if let sessionId = session.id,
               sessionManager.paneHasRunningProcess(for: sessionId, paneId: activePaneId()) {
                pendingCloseAction = .pane
                showCloseConfirmation = true
            } else {
                executeClosePaneOnly()
            }
        }
    }

    func executeCloseAction() {
        showCloseConfirmation = false

        switch pendingCloseAction {
        case .pane:
            executeClosePaneOnly()
        case .tab:
            closeTab()
        }
    }

    func executeClosePaneOnly() {
        guard !isClosingSession else { return }

        let paneIdToClose = activePaneId()
        guard layout.allPaneIds().contains(paneIdToClose) else { return }
        guard !closingPaneIds.contains(paneIdToClose) else { return }

        closingPaneIds.insert(paneIdToClose)
        paneVoiceRecordingStates.removeValue(forKey: paneIdToClose)

        guard let newLayout = layout.removingPane(paneIdToClose) else {
            closeTab()
            return
        }

        transferFocus(from: paneIdToClose, to: newLayout.allPaneIds().first)
        layout = newLayout

        DispatchQueue.main.async { [session, sessionManager] in
            if let sessionId = session.id {
                sessionManager.removeTerminal(for: sessionId, paneId: paneIdToClose)
            }

            if Self.sessionPersistenceEnabled {
                Task {
                    await TmuxSessionRuntime.shared.killSession(paneId: paneIdToClose)
                }
            }
        }
    }

    func closeTab() {
        guard !isClosingSession else { return }
        isClosingSession = true
        showCloseConfirmation = false
        layoutSaveTask?.cancel()
        focusSaveTask?.cancel()
        contextSaveTask?.cancel()
        deactivateSplitActions()

        let allPaneIds = layout.allPaneIds()
        closingPaneIds.formUnion(allPaneIds)
        for paneId in allPaneIds {
            paneVoiceRecordingStates.removeValue(forKey: paneId)
        }
        focusedPaneVoiceRecording = false

        if let sessionId = session.id {
            for paneId in allPaneIds {
                sessionManager.removeTerminal(for: sessionId, paneId: paneId)
            }
        }

        if Self.sessionPersistenceEnabled {
            Task {
                for paneId in allPaneIds {
                    await TmuxSessionRuntime.shared.killSession(paneId: paneId)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak session] in
            guard let session,
                  !session.isDeleted,
                  let context = session.managedObjectContext else { return }
            context.delete(session)
            do {
                try context.save()
            } catch {
                Logger.terminal.error("Failed to delete terminal session: \(error.localizedDescription)")
            }
        }
    }
}
