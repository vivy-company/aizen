//
//  TerminalSplitController+TabClose.swift
//  aizen
//

import Foundation
import CoreData
import os

extension TerminalSplitController {
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
