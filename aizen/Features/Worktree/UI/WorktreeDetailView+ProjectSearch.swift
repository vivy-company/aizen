import AppKit
import SwiftUI

extension WorktreeDetailView {
    func openFile(_ filePath: String) {
        openFile(SearchOpenRequest(path: filePath))
    }

    func openFile(_ request: SearchOpenRequest) {
        searchOpenRequest = request
        selectedTab = "files"
    }

    func showProjectSearch(mode: ProjectSearchMode) {
        if let existing = projectSearchWindowController, existing.window?.isVisible == true {
            if existing.currentMode == mode {
                existing.closeWindow()
                projectSearchWindowController = nil
            } else {
                existing.setMode(mode)
            }
            return
        }

        guard let worktreePath = worktree.path else { return }

        let windowController = ProjectSearchWindowController(
            worktreePath: worktreePath,
            initialMode: mode,
            onSelection: { request in
                self.openFile(request)
            }
        )

        projectSearchWindowController = windowController
        windowController.showWindow(nil)
    }
}
