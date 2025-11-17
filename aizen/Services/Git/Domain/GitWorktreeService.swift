//
//  GitWorktreeService.swift
//  aizen
//
//  Domain service for Git worktree operations
//

import Foundation

struct WorktreeInfo {
    let path: String
    let branch: String
    let commit: String
    let isPrimary: Bool
}

actor GitWorktreeService: GitDomainService {
    let executor: GitCommandExecutor

    init(executor: GitCommandExecutor) {
        self.executor = executor
    }

    func listWorktrees(at repoPath: String) async throws -> [WorktreeInfo] {
        let output = try await executor.executeGit(arguments: ["worktree", "list", "--porcelain"], at: repoPath)
        return parseWorktreeList(output, repositoryPath: repoPath)
    }

    func addWorktree(at repoPath: String, path: String, branch: String, createBranch: Bool = false, baseBranch: String? = nil) async throws {
        var arguments = ["worktree", "add"]

        if createBranch {
            arguments.append("-b")
            arguments.append(branch)
        }

        arguments.append(path)

        // If creating a new branch, specify the base branch
        if createBranch, let baseBranch = baseBranch {
            arguments.append(baseBranch)
        } else if !createBranch {
            // If not creating, just checkout the existing branch
            arguments.append(branch)
        }

        try await executeVoid(arguments, at: repoPath)

        // Pull LFS objects if LFS is enabled in the repository
        try await pullLFSObjects(at: path)
    }

    func pullLFSObjects(at worktreePath: String) async throws {
        // Check if git-lfs is installed and repository uses LFS
        do {
            let lfsFiles = try await executor.executeGit(arguments: ["lfs", "ls-files"], at: worktreePath)

            // If LFS is being used (command succeeds and has output), pull the objects
            if !lfsFiles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await executeVoid(["lfs", "pull"], at: worktreePath)
            }
        } catch {
            // LFS not installed or not used in this repo - skip silently
            // This is expected behavior, not an error
        }
    }

    func removeWorktree(at worktreePath: String, repoPath: String, force: Bool = false) async throws {
        var arguments = ["worktree", "remove"]

        if force {
            arguments.append("--force")
        }

        arguments.append(worktreePath)

        try await executeVoid(arguments, at: repoPath)
    }

    // MARK: - Private Helpers

    private func parseWorktreeList(_ output: String, repositoryPath: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentWorktree: [String: String] = [:]

        // Use components(separatedBy:) instead of split() to preserve empty strings
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                if let path = currentWorktree["worktree"],
                   let branch = currentWorktree["branch"],
                   let commit = currentWorktree["HEAD"] {

                    let cleanBranch = branch.replacingOccurrences(of: "refs/heads/", with: "")
                    let isPrimary = path == repositoryPath

                    worktrees.append(WorktreeInfo(
                        path: path,
                        branch: cleanBranch,
                        commit: commit,
                        isPrimary: isPrimary
                    ))
                }
                currentWorktree.removeAll()
                continue
            }

            let components = trimmedLine.split(separator: " ", maxSplits: 1).map(String.init)
            if components.count == 2 {
                currentWorktree[components[0]] = components[1]
            }
        }

        // Handle last worktree
        if let path = currentWorktree["worktree"],
           let branch = currentWorktree["branch"],
           let commit = currentWorktree["HEAD"] {

            let cleanBranch = branch.replacingOccurrences(of: "refs/heads/", with: "")
            let isPrimary = path == repositoryPath

            worktrees.append(WorktreeInfo(
                path: path,
                branch: cleanBranch,
                commit: commit,
                isPrimary: isPrimary
            ))
        }

        return worktrees
    }
}
