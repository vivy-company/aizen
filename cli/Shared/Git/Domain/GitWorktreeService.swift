//
//  GitWorktreeService.swift
//  aizen
//
//  Domain service for Git worktree operations using libgit2
//

import Foundation

nonisolated struct WorktreeInfo: Sendable {
    let path: String
    let branch: String
    let commit: String
    let isPrimary: Bool
    let isDetached: Bool
}

actor GitWorktreeService {

    func listWorktrees(at repoPath: String) async throws -> [WorktreeInfo] {
        return try await Task.detached {
            let repo = try Libgit2Repository(path: repoPath)
            let worktrees = try repo.listWorktrees()

            return worktrees.map { wt in
                // Get commit hash for the worktree
                var commit = ""
                if let wtPath = wt.path.isEmpty ? nil : wt.path {
                    if let wtRepo = try? Libgit2Repository(path: wtPath) {
                        if let log = try? wtRepo.log(limit: 1), let first = log.first {
                            commit = first.shortOid
                        }
                    }
                }

                // Determine branch name
                let branchName: String
                let isDetached: Bool
                if let branch = wt.branch {
                    branchName = branch
                    isDetached = false
                } else if commit.isEmpty {
                    // No commits yet - try to get branch name from HEAD symbolic ref
                    branchName = Self.getInitialBranchName(at: wt.path) ?? "main"
                    isDetached = false
                } else {
                    branchName = "detached at \(commit.prefix(7))"
                    isDetached = true
                }

                return WorktreeInfo(
                    path: wt.path,
                    branch: branchName,
                    commit: commit,
                    isPrimary: wt.isMain,
                    isDetached: isDetached
                )
            }
        }.value
    }

    private static func getInitialBranchName(at path: String) -> String? {
        // Read HEAD file to get initial branch for empty repos
        let headPath = (path as NSString).appendingPathComponent(".git/HEAD")
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8) else {
            return nil
        }
        // Format: "ref: refs/heads/main\n"
        if content.hasPrefix("ref: refs/heads/") {
            let branch = content.dropFirst("ref: refs/heads/".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        }
        return nil
    }

    func addWorktree(at repoPath: String, path: String, branch: String, createBranch: Bool = false, baseBranch: String? = nil) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: repoPath)

            // Generate a unique worktree name from the path
            let worktreeName = URL(fileURLWithPath: path).lastPathComponent

            try repo.addWorktree(
                name: worktreeName,
                path: path,
                branch: branch,
                createBranch: createBranch,
                baseBranch: baseBranch
            )
        }.value

        // Pull LFS objects if LFS is enabled in the repository
        // This is a best-effort operation - don't fail worktree creation if LFS pull fails
        do {
            try await pullLFSObjects(at: path)
        } catch {
            // LFS pull failed - non-fatal
        }
    }

    func pullLFSObjects(at worktreePath: String) async throws {
        // LFS operations still require shell commands as libgit2 doesn't support LFS
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["lfs", "ls-files"]
            process.currentDirectoryURL = URL(fileURLWithPath: worktreePath)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try? pipe.fileHandleForReading.close()
            let output = String(data: data, encoding: .utf8) ?? ""

            // If LFS is being used, pull the objects
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pullProcess = Process()
                pullProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                pullProcess.arguments = ["lfs", "pull"]
                pullProcess.currentDirectoryURL = URL(fileURLWithPath: worktreePath)
                pullProcess.standardOutput = FileHandle.nullDevice
                pullProcess.standardError = FileHandle.nullDevice

                try pullProcess.run()
                pullProcess.waitUntilExit()
            }
        }.value
    }

    func removeWorktree(at worktreePath: String, repoPath: String, force: Bool = false) async throws {
        try await Task.detached {
            let repo = try Libgit2Repository(path: repoPath)

            // Find worktree name from path
            let worktrees = try repo.listWorktrees()
            guard let worktree = worktrees.first(where: { $0.path == worktreePath }) else {
                throw Libgit2Error.worktreeNotFound(worktreePath)
            }

            try repo.removeWorktree(name: worktree.name, force: force)
        }.value
    }
}
