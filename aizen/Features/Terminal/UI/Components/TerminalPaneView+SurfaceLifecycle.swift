import Foundation
import GhosttyKit
import SwiftUI

extension TerminalPaneView {
    func resolveSurfaceIfNeeded() {
        if let existing = surfaceView {
            surfaceAdapter.applyCallbacks(to: existing)
            existing.setGhosttyFocused(isFocused)
            return
        }

        if let sessionId = session.id,
           let existing = sessionManager.getTerminal(for: sessionId, paneId: paneId) {
            surfaceAdapter.applyCallbacks(to: existing)
            existing.setGhosttyFocused(isFocused)
            surfaceView = existing
            return
        }

        ghosttyApp.ensureRunning()

        guard let app = ghosttyApp.app,
              let worktreePath = surfaceAdapter.worktreePath else {
            return
        }

        let created = AizenTerminalSurfaceView(
            frame: .zero,
            worktreePath: worktreePath,
            ghosttyApp: app,
            appWrapper: ghosttyApp,
            paneId: paneId,
            command: surfaceAdapter.initialCommand
        )
        surfaceAdapter.applyCallbacks(to: created)
        surfaceAdapter.store(surface: created)
        created.setGhosttyFocused(isFocused)
        surfaceView = created
    }

    func requestSurfaceFocus() {
        resolveSurfaceIfNeeded()
        guard let surface = surfaceView else {
            return
        }

        guard surface.window?.firstResponder !== surface else { return }
        Ghostty.moveFocus(to: surface)
    }
}
