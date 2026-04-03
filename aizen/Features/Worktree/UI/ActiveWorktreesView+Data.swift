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

    var monitorRows: [ActiveWorktreesMonitorRow] {
        let seeds = filteredWorktrees.map(buildSeed(for:))
        guard !seeds.isEmpty else { return [] }

        let scores = seeds.map { activityScore(for: $0) }
        let scoreTotal: Double = Swift.max(scores.reduce(0.0, +), 0.001)

        var rows: [ActiveWorktreesMonitorRow] = []
        rows.reserveCapacity(seeds.count)

        for index in seeds.indices {
            let seed = seeds[index]
            let score = scores[index]
            let cpuShare = Swift.min(
                99.9,
                Swift.max(
                    0.0,
                    (metrics.cpuPercent * (score / scoreTotal)) + (Double(seed.runtime.runningPanes) * 0.35)
                )
            )

            let estimatedMemory = UInt64(Swift.max(
                64_000_000,
                130_000_000 +
                    (seed.counts.chats * 50_000_000) +
                    (seed.counts.terminals * 88_000_000) +
                    (seed.counts.browsers * 120_000_000) +
                    (seed.counts.files * 20_000_000) +
                    (seed.runtime.livePanes * 28_000_000)
            ))

            let energyImpact = Swift.min(
                100,
                (cpuShare * 1.3) +
                    Double(seed.runtime.runningPanes * 8) +
                    Double(seed.counts.total)
            )

            let threads = Swift.max(
                1,
                (seed.counts.total * 4) +
                    (seed.runtime.livePanes * 14) +
                    (seed.runtime.runningPanes * 6)
            )

            let idleWakeUps = Int((energyImpact * 1.8).rounded()) + (threads / 3)

            rows.append(
                ActiveWorktreesMonitorRow(
                    id: seed.id,
                    worktree: seed.worktree,
                    processName: seed.processName,
                    workspaceName: seed.workspaceName,
                    path: seed.path,
                    cpuPercent: cpuShare,
                    memoryBytes: estimatedMemory,
                    energyImpact: energyImpact,
                    threadCount: threads,
                    idleWakeUps: idleWakeUps,
                    totalSessions: seed.counts.total,
                    counts: seed.counts,
                    runtime: seed.runtime,
                    lastAccessed: seed.lastAccessed
                )
            )
        }

        return rows
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
