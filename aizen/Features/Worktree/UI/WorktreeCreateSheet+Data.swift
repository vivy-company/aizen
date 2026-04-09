//
//  WorktreeCreateSheet+Data.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import SwiftUI

extension WorktreeCreateSheet {
    var repositoryWorktrees: [Worktree] {
        workspaceGraphQueryController.worktrees(in: repository)
    }

    var branchNameTemplates: [String] {
        (try? JSONDecoder().decode([String].self, from: branchNameTemplatesData)) ?? []
    }

    var isGitProject: Bool {
        guard let repoPath = repository.path else { return false }
        return GitUtils.isGitRepository(at: repoPath)
    }

    var sourcePath: String? {
        if let primary = repositoryWorktrees.first(where: { $0.isPrimary }),
           let path = primary.path {
            return path
        }
        return repository.path
    }

    private var environmentRootDirectory: URL? {
        guard let repoPath = repository.path else { return nil }
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("aizen/worktrees")
            .appendingPathComponent(repoName)
    }

    var targetPath: String? {
        guard let root = environmentRootDirectory else { return nil }
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return root.appendingPathComponent(trimmedName).path
    }

    var existingWorktreeNames: [String] {
        repositoryWorktrees.compactMap(\.branch)
    }

    var defaultBaseBranch: String {
        if let mainWorktree = repositoryWorktrees.first(where: { $0.isPrimary }) {
            return mainWorktree.branch ?? "main"
        }
        return "main"
    }

    var hasSubmodules: Bool {
        !detectedSubmodules.isEmpty
    }

    var selectedSubmoduleCount: Int {
        let available = Set(detectedSubmodules.map(\.path))
        return selectedSubmodulePaths.intersection(available).count
    }

    var branchNamePrompt: String {
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "feature-login-auth"
        }
        return "feature/\(trimmedName)"
    }

    var independentMethodDescription: String {
        switch independentMethod {
        case .clone:
            return "Clone creates a separate Git repository using git clone --local. It keeps .git, history, branches, and remotes."
        case .copy:
            return "Copy runs rsync and excludes .git. It only copies the current files, so the new environment is not a Git checkout."
        }
    }

    func submoduleSelectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedSubmodulePaths.contains(path) },
            set: { selected in
                if selected {
                    selectedSubmodulePaths.insert(path)
                } else {
                    selectedSubmodulePaths.remove(path)
                    if selectedSubmodulePaths.isEmpty {
                        matchSubmoduleBranchToEnvironment = false
                    }
                }
            }
        )
    }

    var modeBinding: Binding<EnvironmentCreationMode> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode
                if newMode == .independent && !isGitProject {
                    independentMethod = .copy
                }
            }
        )
    }

    var branchNameBinding: Binding<String> {
        Binding(
            get: { branchName },
            set: { newValue in
                branchName = newValue
                validateBranchName()
            }
        )
    }

    var initializeSubmodulesBinding: Binding<Bool> {
        Binding(
            get: { initializeSubmodules },
            set: { newValue in
                initializeSubmodules = newValue
                if !newValue {
                    matchSubmoduleBranchToEnvironment = false
                }
            }
        )
    }

    var environmentNameWarning: String? {
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "Environment name is required."
        }
        if trimmedName.contains("/") {
            return "Environment name cannot contain '/'."
        }
        if let destination = targetPath, FileManager.default.fileExists(atPath: destination) {
            return "Destination already exists."
        }
        return nil
    }

    var isValid: Bool {
        if environmentNameWarning != nil {
            return false
        }

        switch mode {
        case .linked:
            return isGitProject && !branchName.isEmpty && validationWarning == nil
        case .independent:
            return sourcePath != nil
        }
    }
}
