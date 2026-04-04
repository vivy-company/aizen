//
//  WorktreeRuntime.swift
//  aizen
//
//  Shared per-worktree runtime ownership for Git summary, working diff,
//  workflow refresh, and Xcode detection.
//

import Combine
import Foundation

enum WorktreeRuntimeSurface: Hashable {
    case detail
    case gitPanel
    case companionDiff
}

@MainActor
final class WorktreeRuntime: ObservableObject {
    let worktreePath: String
    let summaryStore: GitSummaryStore
    let diffStore: GitDiffRuntimeStore
    let operationService: GitOperationService
    let workflowService = WorkflowService()
    let xcodeBuildManager = XcodeBuildStore()

    var attachedSurfaces = Set<WorktreeRuntimeSurface>()
    var gitPanelShowsWorkingDiff = false
    private var workflowVisible = false
    private var xcodeVisible = false
    var watcherToken: UUID?
    private var workflowConfigured = false
    var gitRefreshSuspensionCount = 0
    private var idleStateHandler: ((String, Bool) -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init(worktreePath: String) {
        self.worktreePath = worktreePath
        self.summaryStore = GitSummaryStore(worktreePath: worktreePath)
        self.diffStore = GitDiffRuntimeStore(worktreePath: worktreePath)

        let summaryStore = self.summaryStore
        let diffStore = self.diffStore
        self.operationService = GitOperationService(worktreePath: worktreePath) {
            summaryStore.markStale()
            summaryStore.refresh(reason: "git-mutation", tier: .full, force: true)
            diffStore.markStale()
            diffStore.refresh(force: true)
        }

        summaryStore.$currentStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleStatusChange(status)
            }
            .store(in: &cancellables)
    }

    func setIdleStateHandler(_ handler: @escaping (String, Bool) -> Void) {
        idleStateHandler = handler
    }

    func attachDetail(showXcode: Bool) {
        let wasIdle = attachedSurfaces.isEmpty
        attachedSurfaces.insert(.detail)
        xcodeVisible = showXcode

        if wasIdle {
            idleStateHandler?(worktreePath, false)
        }

        ensureWatcher()
        summaryStore.refresh(reason: "detail-attach", tier: .summary, force: summaryStore.isStale)
        syncXcodeVisibility()
    }

    func updateDetailOptions(showXcode: Bool) {
        guard attachedSurfaces.contains(.detail) else { return }
        xcodeVisible = showXcode
        syncXcodeVisibility()
    }

    func detachDetail() {
        attachedSurfaces.remove(.detail)
        xcodeVisible = false
        syncAfterSurfaceChange()
    }

    func setGitPanelVisible(_ visible: Bool, showsWorkingDiff: Bool, showsWorkflow: Bool) {
        let wasIdle = attachedSurfaces.isEmpty

        if visible {
            attachedSurfaces.insert(.gitPanel)
            gitPanelShowsWorkingDiff = showsWorkingDiff
            workflowVisible = showsWorkflow

            if wasIdle {
                idleStateHandler?(worktreePath, false)
            }

            ensureWatcher()
            summaryStore.refresh(reason: "git-panel-visible", tier: .full, force: summaryStore.isStale)
            syncWorkingDiffVisibility(forceImmediateRefresh: true)
            syncWorkflowVisibility()
            return
        }

        attachedSurfaces.remove(.gitPanel)
        gitPanelShowsWorkingDiff = false
        workflowVisible = false
        workflowService.setAutoRefreshEnabled(false)
        workflowService.clearSelection()
        syncAfterSurfaceChange()
    }

    func setCompanionDiffVisible(_ visible: Bool) {
        let wasIdle = attachedSurfaces.isEmpty

        if visible {
            attachedSurfaces.insert(.companionDiff)

            if wasIdle {
                idleStateHandler?(worktreePath, false)
            }

            ensureWatcher()
            summaryStore.refresh(reason: "companion-diff-visible", tier: .summary, force: summaryStore.isStale)
            syncWorkingDiffVisibility(forceImmediateRefresh: true)
            return
        }

        attachedSurfaces.remove(.companionDiff)
        diffStore.setRefreshSuspended(false)
        syncAfterSurfaceChange()
    }

    func setCompanionDiffRefreshSuspended(_ suspended: Bool) {
        guard attachedSurfaces.contains(.companionDiff) else { return }
        diffStore.setRefreshSuspended(suspended)
    }

    private func handleStatusChange(_ status: GitStatus) {
        guard workflowConfigured else { return }
        let branch = status.currentBranch.isEmpty ? "main" : status.currentBranch
        Task {
            await workflowService.updateBranch(branch)
        }
    }

    private func syncAfterSurfaceChange() {
        syncWorkingDiffVisibility(forceImmediateRefresh: false)
        syncWorkflowVisibility()
        syncXcodeVisibility()

        guard attachedSurfaces.isEmpty else { return }

        if let watcherToken {
            let path = worktreePath
            Task {
                await GitIndexWatchCenter.shared.removeSubscriber(worktreePath: path, id: watcherToken)
            }
        }
        watcherToken = nil
        idleStateHandler?(worktreePath, true)
    }

    private func syncWorkingDiffVisibility(forceImmediateRefresh: Bool) {
        diffStore.setVisible(hasWorkingDiffConsumer)
        guard hasWorkingDiffConsumer else { return }
        if forceImmediateRefresh || diffStore.isStale {
            diffStore.refresh(force: true)
        }
    }

    private func syncWorkflowVisibility() {
        guard workflowVisible else {
            workflowService.setAutoRefreshEnabled(false)
            workflowService.clearSelection()
            return
        }

        let branch = summaryStore.currentStatus.currentBranch.isEmpty ? "main" : summaryStore.currentStatus.currentBranch
        if !workflowConfigured {
            workflowConfigured = true
            Task {
                await workflowService.configure(repoPath: worktreePath, branch: branch)
            }
            return
        }

        workflowService.setAutoRefreshEnabled(true)
    }

    private func syncXcodeVisibility() {
        guard xcodeVisible else { return }
        xcodeBuildManager.detectProject(at: worktreePath)
    }
}
