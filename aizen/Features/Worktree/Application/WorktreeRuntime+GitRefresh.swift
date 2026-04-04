//
//  WorktreeRuntime+GitRefresh.swift
//  aizen
//
//  Git watcher and refresh orchestration for worktree runtime
//

import Foundation

extension WorktreeRuntime {
    func setGitRefreshSuspended(_ suspended: Bool) {
        if suspended {
            gitRefreshSuspensionCount += 1
            return
        }

        guard gitRefreshSuspensionCount > 0 else { return }
        gitRefreshSuspensionCount -= 1

        guard gitRefreshSuspensionCount == 0 else { return }

        if !attachedSurfaces.isEmpty {
            let tier: GitSummaryStore.RefreshTier = attachedSurfaces.contains(.gitPanel) ? .full : .summary
            summaryStore.refresh(reason: "git-refresh-resume", tier: tier)
        }
        if hasWorkingDiffConsumer {
            diffStore.refresh()
        }
    }

    func refreshSummary(lightweight: Bool = false) {
        let tier: GitSummaryStore.RefreshTier = lightweight ? .summary : .full
        summaryStore.refresh(reason: "runtime-refresh-summary", tier: tier, force: true)
    }

    func refreshWorkingDiffNow() {
        guard hasWorkingDiffConsumer else { return }
        diffStore.refresh(force: true)
    }

    var hasWorkingDiffConsumer: Bool {
        gitPanelShowsWorkingDiff || attachedSurfaces.contains(.companionDiff)
    }

    func handleGitWatcherEvent() {
        summaryStore.markStale()
        diffStore.markStale()

        guard gitRefreshSuspensionCount == 0 else { return }

        if !attachedSurfaces.isEmpty {
            let tier: GitSummaryStore.RefreshTier = attachedSurfaces.contains(.gitPanel) ? .full : .summary
            summaryStore.refresh(reason: "git-watch", tier: tier)
        }
        if hasWorkingDiffConsumer {
            diffStore.refresh()
        }
    }

    func ensureWatcher() {
        guard watcherToken == nil, !worktreePath.isEmpty else { return }
        let path = worktreePath

        Task { [weak self] in
            let token = await GitIndexWatchCenter.shared.addSubscriber(worktreePath: path) { [weak self] in
                self?.handleGitWatcherEvent()
            }
            await MainActor.run {
                guard let self, self.watcherToken == nil else { return }
                self.watcherToken = token
            }
        }
    }
}
