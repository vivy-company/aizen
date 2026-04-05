import Foundation

extension ActiveWorktreesView {
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
}
