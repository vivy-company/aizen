import Foundation

extension WorktreeDetailView {
    func loadTabState() {
        guard let worktreeId = worktree.id else { return }

        if tabStateManager.hasStoredState(for: worktreeId) {
            let state = tabStateManager.getState(for: worktreeId)
            selectedTab = state.viewType
            viewModel.selectedChatSessionId = state.chatSessionId
            viewModel.selectedTerminalSessionId = state.terminalSessionId
            viewModel.selectedBrowserSessionId = state.browserSessionId
            viewModel.selectedFileSessionId = state.fileSessionId
        } else {
            selectedTab = tabConfig.effectiveDefaultTab(
                showChat: showChatTab,
                showTerminal: showTerminalTab,
                showFiles: showFilesTab,
                showBrowser: showBrowserTab
            )
        }
    }

    func saveTabState() {
        guard let worktreeId = worktree.id else { return }
        tabStateManager.saveViewType(selectedTab, for: worktreeId)
    }

    func openInLastApp() {
        guard let app = lastOpenedApp else {
            if let finder = appDetector.getApps(for: .finder).first {
                openInDetectedApp(finder)
            }
            return
        }
        openInDetectedApp(app)
    }

    func openInDetectedApp(_ app: DetectedApp) {
        guard let path = worktree.path else { return }
        lastOpenedApp = app
        appDetector.openPath(path, with: app)
    }
}
