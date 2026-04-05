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

    var workspaceGroups: [ActiveWorktreesWorkspaceGroup] {
        var groups: [NSManagedObjectID: ActiveWorktreesWorkspaceGroup] = [:]
        var otherWorktrees: [Worktree] = []

        for worktree in activeWorktrees {
            guard let workspace = worktree.repository?.workspace, !workspace.isDeleted else {
                otherWorktrees.append(worktree)
                continue
            }

            let id = workspace.objectID
            if var existing = groups[id] {
                existing.worktrees.append(worktree)
                groups[id] = existing
            } else {
                groups[id] = ActiveWorktreesWorkspaceGroup(
                    id: id.uriRepresentation().absoluteString,
                    workspaceId: id,
                    name: workspace.name ?? "Workspace",
                    colorHex: workspace.colorHex,
                    order: Int(workspace.order),
                    worktrees: [worktree],
                    isOther: false
                )
            }
        }

        var sorted = groups.values.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if !otherWorktrees.isEmpty {
            sorted.append(
                ActiveWorktreesWorkspaceGroup(
                    id: "other",
                    workspaceId: nil,
                    name: "Other",
                    colorHex: nil,
                    order: Int.max,
                    worktrees: otherWorktrees,
                    isOther: true
                )
            )
        }

        return sorted
    }

    var scopedWorktrees: [Worktree] {
        switch selectedScope {
        case .all:
            return activeWorktrees
        case .workspace(let id):
            return workspaceGroups.first { $0.workspaceId == id }?.worktrees ?? []
        case .other:
            return workspaceGroups.first { $0.isOther }?.worktrees ?? []
        }
    }

    var filteredWorktrees: [Worktree] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return scopedWorktrees.sorted(by: worktreeSort)
        }

        return scopedWorktrees.filter { worktree in
            let workspaceName = worktree.repository?.workspace?.name ?? ""
            let repositoryName = worktree.repository?.name ?? ""
            let branch = worktree.branch ?? ""
            let path = worktree.path ?? ""

            return workspaceName.localizedCaseInsensitiveContains(query) ||
                repositoryName.localizedCaseInsensitiveContains(query) ||
                branch.localizedCaseInsensitiveContains(query) ||
                path.localizedCaseInsensitiveContains(query)
        }
        .sorted(by: worktreeSort)
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

    var scopeLabel: String {
        switch selectedScope {
        case .all:
            return "All Environments"
        case .workspace(let id):
            return workspaceGroups.first(where: { $0.workspaceId == id })?.name ?? "Workspace"
        case .other:
            return "Other"
        }
    }
}
