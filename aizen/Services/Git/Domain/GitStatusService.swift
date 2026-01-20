//
//  GitStatusService.swift
//  aizen
//
//  Domain service for Git status queries using libgit2
//

import Foundation

nonisolated struct DetailedGitStatus: Sendable {
    let stagedFiles: [String]
    let modifiedFiles: [String]
    let untrackedFiles: [String]
    let conflictedFiles: [String]
    let currentBranch: String?
    let aheadBy: Int
    let behindBy: Int
    let additions: Int
    let deletions: Int
}

actor GitStatusService {

    func getDetailedStatus(
        at path: String,
        includeUntracked: Bool = true,
        includeDiffStats: Bool = true
    ) async throws -> DetailedGitStatus {
        let repo = try Libgit2Repository(path: path)
        let status = try repo.status(includeUntracked: includeUntracked)

        // Get current branch name
        let currentBranch = try? repo.currentBranchName()

        // Get ahead/behind counts
        let aheadBehind = (try? repo.headAheadBehind()) ?? (ahead: 0, behind: 0)
        let aheadBy = aheadBehind.ahead
        let behindBy = aheadBehind.behind

        // Calculate additions/deletions from diff (can be expensive on large repos)
        let diffStats: Libgit2DiffStats
        if includeDiffStats {
            diffStats = (try? repo.diffStats()) ?? Libgit2DiffStats(filesChanged: 0, insertions: 0, deletions: 0)
        } else {
            diffStats = Libgit2DiffStats(filesChanged: 0, insertions: 0, deletions: 0)
        }

        // Map entries to file paths
        let stagedFiles = status.staged.map { $0.path }
        let modifiedFiles = status.modified.map { $0.path }
        let untrackedFiles = status.untracked.map { $0.path }
        let conflictedFiles = status.conflicted.map { $0.path }

        return DetailedGitStatus(
            stagedFiles: stagedFiles,
            modifiedFiles: modifiedFiles,
            untrackedFiles: untrackedFiles,
            conflictedFiles: conflictedFiles,
            currentBranch: currentBranch,
            aheadBy: aheadBy,
            behindBy: behindBy,
            additions: diffStats.insertions,
            deletions: diffStats.deletions
        )
    }

    func getCurrentBranch(at path: String) async throws -> String {
        let repo = try Libgit2Repository(path: path)
        guard let branch = try repo.currentBranchName() else {
            throw Libgit2Error.referenceNotFound("HEAD")
        }
        return branch
    }

    func getBranchStatus(at path: String) async throws -> (ahead: Int, behind: Int) {
        let repo = try Libgit2Repository(path: path)

        guard (try? repo.currentBranchName()) != nil else {
            return (0, 0)
        }

        return (try? repo.headAheadBehind()) ?? (0, 0)
    }

    func hasUnsavedChanges(at worktreePath: String) async throws -> Bool {
        let repo = try Libgit2Repository(path: worktreePath)
        let status = try repo.status()
        return status.hasChanges
    }
}
