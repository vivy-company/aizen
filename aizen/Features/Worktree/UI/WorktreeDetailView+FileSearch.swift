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

    func showFileSearch() {
        if let existing = fileSearchWindowController, existing.window?.isVisible == true {
            existing.closeWindow()
            fileSearchWindowController = nil
            return
        }

        guard let worktreePath = worktree.path else { return }

        let windowController = FileSearchWindowController(
            worktreePath: worktreePath,
            onFileSelected: { filePath in
                self.openFile(filePath)
            }
        )

        fileSearchWindowController = windowController
        windowController.showWindow(nil)
    }
}
