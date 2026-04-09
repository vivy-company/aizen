import Foundation

extension WorktreeDetailView {
    func loadTabState() {
        scene.restorePersistedStateIfNeeded(
            defaultTab: tabConfig.effectiveDefaultTab(
                showChat: showChatTab,
                showTerminal: showTerminalTab,
                showFiles: showFilesTab,
                showBrowser: showBrowserTab
            )
        )
        hasLoadedTabState = true
    }

    func saveTabState() {
        scene.saveSelectedTabIfNeeded()
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
