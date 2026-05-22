import SwiftUI

extension WorktreeCreateSheet {
    func loadSubmodules() {
        guard isGitProject else {
            detectedSubmodules = []
            initializeSubmodules = false
            selectedSubmodulePaths = []
            matchSubmoduleBranchToEnvironment = false
            loadingSubmodules = false
            return
        }

        loadingSubmodules = true
        Task {
            let submodules = await repositoryManager.listSubmodules(for: repository)
            await MainActor.run {
                detectedSubmodules = submodules
                initializeSubmodules = !submodules.isEmpty
                selectedSubmodulePaths = Set(submodules.map(\.path))
                if submodules.isEmpty {
                    matchSubmoduleBranchToEnvironment = false
                }
                loadingSubmodules = false
            }
        }
    }

    func createEnvironment() {
        guard !isProcessing, isValid else { return }
        guard let destinationPath = targetPath else { return }

        let baseBranchName = selectedBranch?.name ?? defaultBaseBranch
        let source = sourcePath

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let createdWorktree: Worktree
                switch mode {
                case .linked:
                    let submoduleOptions: WorkspaceRepositoryStore.LinkedEnvironmentSubmoduleOptions
                    let selectedPaths = detectedSubmodules
                        .map(\.path)
                        .filter { selectedSubmodulePaths.contains($0) }
                    if initializeSubmodules && !selectedPaths.isEmpty {
                        submoduleOptions = WorkspaceRepositoryStore.LinkedEnvironmentSubmoduleOptions(
                            initialize: true,
                            recursive: includeNestedSubmodules,
                            paths: selectedPaths,
                            matchBranchToEnvironment: matchSubmoduleBranchToEnvironment && !branchName.isEmpty
                        )
                    } else {
                        submoduleOptions = .disabled
                    }

                    createdWorktree = try await repositoryManager.addLinkedEnvironment(
                        to: repository,
                        path: destinationPath,
                        branch: branchName,
                        createBranch: true,
                        baseBranch: baseBranchName,
                        submoduleOptions: submoduleOptions,
                        runPostCreateActions: shouldRunPostCreateActions
                    )
                case .independent:
                    guard let source else {
                        throw Libgit2Error.invalidPath("Source path is unavailable")
                    }
                    let method: WorkspaceRepositoryStore.IndependentEnvironmentMethod = isGitProject ? independentMethod : .copy
                    createdWorktree = try await repositoryManager.addIndependentEnvironment(
                        to: repository,
                        path: destinationPath,
                        sourcePath: source,
                        method: method,
                        runPostCreateActions: shouldRunPostCreateActions
                    )
                }

                await MainActor.run {
                    Analytics.shared.track(
                        .worktreeCreated(
                            source: analyticsWorktreeSource,
                            worktreeCount: analyticsWorktreeCount(afterCreating: createdWorktree)
                        )
                    )
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    if let libgit2Error = error as? Libgit2Error {
                        errorMessage = libgit2Error.errorDescription
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isProcessing = false
                }
            }
        }
    }

    private var analyticsWorktreeSource: AnalyticsWorktreeSource {
        switch mode {
        case .linked:
            return .newBranch
        case .independent:
            return .unknown
        }
    }

    private func analyticsWorktreeCount(afterCreating createdWorktree: Worktree) -> Int {
        let worktrees = createdWorktree.repository?.worktrees as? Set<Worktree>
        return worktrees?.filter { !$0.isDeleted }.count ?? 1
    }
}
