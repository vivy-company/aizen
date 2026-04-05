import SwiftUI

extension GitSidebarHeader {
    var chipBackground: some ShapeStyle {
        Color.white.opacity(0.08)
    }

    var canPerformBulkAction: Bool {
        !isOperationPending && hasAnyChanges
    }

    var hasAnyChanges: Bool {
        !(gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty)
    }

    var headerTitle: String {
        let total = gitStatus.stagedFiles.count + gitStatus.modifiedFiles.count + gitStatus.untrackedFiles.count
        if total == 0 {
            return String(localized: "git.sidebar.noChanges")
        } else if total == 1 {
            return String(localized: "git.sidebar.changesSingular")
        } else {
            return String(localized: "git.sidebar.changes \(total)")
        }
    }
}
