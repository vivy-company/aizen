//
//  WorktreeRuntimeCoordinator.swift
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

    private var attachedSurfaces = Set<WorktreeRuntimeSurface>()
    private var gitPanelShowsWorkingDiff = false
    private var workflowVisible = false
    private var xcodeVisible = false
    private var watcherToken: UUID?
    private var workflowConfigured = false
    private var gitRefreshSuspensionCount = 0
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

    private var hasWorkingDiffConsumer: Bool {
        gitPanelShowsWorkingDiff || attachedSurfaces.contains(.companionDiff)
    }

    private func handleStatusChange(_ status: GitStatus) {
        guard workflowConfigured else { return }
        let branch = status.currentBranch.isEmpty ? "main" : status.currentBranch
        Task {
            await workflowService.updateBranch(branch)
        }
    }

    private func handleGitWatcherEvent() {
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

    private func ensureWatcher() {
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

@MainActor
final class WorktreeRuntimeCoordinator {
    static let shared = WorktreeRuntimeCoordinator()

    private var runtimes: [String: WorktreeRuntime] = [:]
    private var evictionTasks: [String: Task<Void, Never>] = [:]
    private let idleEvictionDelaySeconds: Double = 60

    private init() {}

    func runtime(for worktreePath: String) -> WorktreeRuntime {
        if let runtime = runtimes[worktreePath] {
            evictionTasks[worktreePath]?.cancel()
            evictionTasks[worktreePath] = nil
            return runtime
        }

        let runtime = WorktreeRuntime(worktreePath: worktreePath)
        runtime.setIdleStateHandler { [weak self] path, isIdle in
            guard let self else { return }
            if isIdle {
                self.scheduleEviction(for: path)
            } else {
                self.evictionTasks[path]?.cancel()
                self.evictionTasks[path] = nil
            }
        }
        runtimes[worktreePath] = runtime
        return runtime
    }

    private func scheduleEviction(for worktreePath: String) {
        evictionTasks[worktreePath]?.cancel()
        let idleDelay = idleEvictionDelaySeconds
        evictionTasks[worktreePath] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(idleDelay))
            } catch {
                return
            }
            await MainActor.run {
                self?.runtimes.removeValue(forKey: worktreePath)
                self?.evictionTasks.removeValue(forKey: worktreePath)
            }
        }
    }
}
