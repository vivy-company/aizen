import AppKit
import Foundation

@MainActor
struct AizenTerminalSurfaceAdapter {
    let session: TerminalSession
    let worktree: Worktree
    let paneId: String
    let sessionManager: TerminalRuntimeStore
    let onProcessExit: () -> Void
    let onFocus: () -> Void
    let onReady: () -> Void
    let onTitleChange: (String) -> Void
    let onProgress: (GhosttyProgressState, Int?) -> Void

    var worktreePath: String? {
        worktree.path
    }

    var sessionId: UUID? {
        session.id
    }

    var initialCommand: String? {
        guard let sessionId else { return nil }
        return sessionManager.getTerminalCount(for: sessionId) == 0 ? session.initialCommand : nil
    }

    func existingSurface() -> AizenTerminalSurfaceView? {
        guard let sessionId else { return nil }
        return sessionManager.getTerminal(for: sessionId, paneId: paneId)
    }

    func store(surface: AizenTerminalSurfaceView) {
        guard let sessionId else { return }
        sessionManager.setTerminal(surface, for: sessionId, paneId: paneId)
    }

    func sendText(_ text: String) {
        guard let sessionId,
              let terminal = sessionManager.getTerminal(for: sessionId, paneId: paneId) else {
            return
        }

        terminal.surfaceModel?.sendText(text)
    }

    func applyCallbacks(to surface: AizenTerminalSurfaceView) {
        surface.onProcessExit = onProcessExit
        surface.onFocus = onFocus
        surface.onReady = onReady
        surface.onTitleChange = onTitleChange
        surface.onProgressReport = onProgress
    }
}
