import SwiftUI

extension WorktreeDetailView {
    func isTabVisible(_ tabId: String) -> Bool {
        switch tabId {
        case "chat": return showChatTab
        case "terminal": return showTerminalTab
        case "files": return showFilesTab
        case "browser": return showBrowserTab
        default: return false
        }
    }

    func selectVisibleTab(at oneBasedIndex: Int) {
        let zeroBased = oneBasedIndex - 1
        guard zeroBased >= 0, zeroBased < visibleTabIds.count else { return }
        selectedTab = visibleTabIds[zeroBased]
    }

    func cycleVisibleTab(step: Int) {
        guard !visibleTabIds.isEmpty else { return }
        guard let currentIndex = visibleTabIds.firstIndex(of: selectedTab) else {
            selectedTab = visibleTabIds[0]
            return
        }

        let count = visibleTabIds.count
        let nextIndex = (currentIndex + step + count) % count
        selectedTab = visibleTabIds[nextIndex]
    }
}
