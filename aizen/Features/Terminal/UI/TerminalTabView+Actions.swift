import os.log
import SwiftUI

extension TerminalTabView {
    func createNewSession(withPreset preset: TerminalPreset? = nil) {
        guard let context = worktree.managedObjectContext else { return }

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.createdAt = Date()
        session.worktree = worktree
        let defaultPaneId = TerminalLayoutDefaults.paneId(sessionId: session.id, focusedPaneId: nil)
        session.focusedPaneId = defaultPaneId
        session.splitLayout = SplitLayoutHelper.encode(TerminalLayoutDefaults.defaultLayout(paneId: defaultPaneId))

        if let preset = preset {
            session.title = preset.name
            session.initialCommand = preset.command
            logger.info("Creating session with preset: \(preset.name), command: \(preset.command)")
        } else {
            session.title = String(
                localized: "worktree.session.terminalTitle",
                defaultValue: "Terminal \(sessions.count + 1)",
                bundle: .main
            )
        }

        do {
            try context.save()
            logger.info("Session saved, initialCommand: \(session.initialCommand ?? "nil")")
            selectedSessionId = session.id
        } catch {
            logger.error("Failed to create terminal session: \(error.localizedDescription)")
        }
    }
}
