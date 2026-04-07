import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {

    /// Get diff between index and workdir (unstaged changes)
    func diffIndexToWorkdir() throws -> [Libgit2DiffDelta] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        opts.flags = UInt32(GIT_DIFF_INCLUDE_UNTRACKED.rawValue)

        let diffError = git_diff_index_to_workdir(&diff, ptr, nil, &opts)
        guard diffError == 0, let d = diff else {
            throw Libgit2Error.from(diffError, context: "diff index to workdir")
        }
        defer { git_diff_free(d) }

        return try parseDiff(d)
    }

    /// Get diff between HEAD and index (staged changes)
    func diffHeadToIndex() throws -> [Libgit2DiffDelta] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var head: OpaquePointer?
        let headError = git_repository_head(&head, ptr)
        guard headError == 0, let h = head else {
            return []
        }
        defer { git_reference_free(h) }

        var commit: OpaquePointer?
        let peelError = git_reference_peel(&commit, h, GIT_OBJECT_COMMIT)
        guard peelError == 0, let c = commit else {
            throw Libgit2Error.from(peelError, context: "peel HEAD")
        }
        defer { git_commit_free(c) }

        var tree: OpaquePointer?
        let treeError = git_commit_tree(&tree, c)
        guard treeError == 0, let t = tree else {
            throw Libgit2Error.from(treeError, context: "get commit tree")
        }
        defer { git_tree_free(t) }

        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))

        let diffError = git_diff_tree_to_index(&diff, ptr, t, nil, &opts)
        guard diffError == 0, let d = diff else {
            throw Libgit2Error.from(diffError, context: "diff tree to index")
        }
        defer { git_diff_free(d) }

        return try parseDiff(d)
    }

    /// Get diff for a specific file
    func diffFile(_ filePath: String) throws -> Libgit2DiffDelta? {
        let allDiffs = try diffIndexToWorkdir()
        return allDiffs.first { $0.newPath == filePath || $0.oldPath == filePath }
    }

    /// Get diff stats (files changed, insertions, deletions)
    func diffStats() throws -> Libgit2DiffStats {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var stagedDiff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))

        var head: OpaquePointer?
        var tree: OpaquePointer? = nil

        if git_repository_head(&head, ptr) == 0, let h = head {
            defer { git_reference_free(h) }

            var commit: OpaquePointer?
            if git_reference_peel(&commit, h, GIT_OBJECT_COMMIT) == 0, let c = commit {
                defer { git_commit_free(c) }
                var t: OpaquePointer?
                if git_commit_tree(&t, c) == 0 {
                    tree = t
                }
            }
        }

        defer { if let t = tree { git_tree_free(t) } }

        let stagedError = git_diff_tree_to_index(&stagedDiff, ptr, tree, nil, &opts)
        if stagedError != 0 {
            stagedDiff = nil
        }
        defer { if let d = stagedDiff { git_diff_free(d) } }

        var unstagedDiff: OpaquePointer?
        opts.flags = UInt32(GIT_DIFF_INCLUDE_UNTRACKED.rawValue)
        let unstagedError = git_diff_index_to_workdir(&unstagedDiff, ptr, nil, &opts)
        if unstagedError != 0 {
            unstagedDiff = nil
        }
        defer { if let d = unstagedDiff { git_diff_free(d) } }

        var totalFiles = 0
        var totalInsertions = 0
        var totalDeletions = 0

        if let d = stagedDiff {
            var stats: OpaquePointer?
            if git_diff_get_stats(&stats, d) == 0, let s = stats {
                defer { git_diff_stats_free(s) }
                totalFiles += git_diff_stats_files_changed(s)
                totalInsertions += git_diff_stats_insertions(s)
                totalDeletions += git_diff_stats_deletions(s)
            }
        }

        if let d = unstagedDiff {
            var stats: OpaquePointer?
            if git_diff_get_stats(&stats, d) == 0, let s = stats {
                defer { git_diff_stats_free(s) }
                totalFiles += git_diff_stats_files_changed(s)
                totalInsertions += git_diff_stats_insertions(s)
                totalDeletions += git_diff_stats_deletions(s)
            }
        }

        return Libgit2DiffStats(
            filesChanged: totalFiles,
            insertions: totalInsertions,
            deletions: totalDeletions
        )
    }
}
