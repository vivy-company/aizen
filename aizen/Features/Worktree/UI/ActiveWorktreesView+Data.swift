import CoreData
import Foundation

extension ActiveWorktreesView {
    var activeWorktrees: [Worktree] {
        worktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            return isActive(worktree)
        }
    }

    var activeWorktreeIDs: [NSManagedObjectID] {
        activeWorktrees.map { $0.objectID }
    }

    var visibleRows: [ActiveWorktreesMonitorRow] {
        monitorRows.filter(rowMatchesSelectedMode)
    }

    var sortedRows: [ActiveWorktreesMonitorRow] {
        var rows = visibleRows
        rows.sort(using: sortOrder)
        return rows
    }

    var totalThreadCount: Int {
        sortedRows.reduce(0) { $0 + $1.threadCount }
    }

    var totalRunningPanes: Int {
        sortedRows.reduce(0) { $0 + $1.runtime.runningPanes }
    }
}
