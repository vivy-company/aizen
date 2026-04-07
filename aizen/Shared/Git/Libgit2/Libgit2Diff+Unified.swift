import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {
    /// Get unified diff string for HEAD (staged + unstaged changes)
    func diffUnified() throws -> String {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var tree: OpaquePointer? = nil
        var head: OpaquePointer?
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

        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        opts.flags = UInt32(GIT_DIFF_INCLUDE_UNTRACKED.rawValue)
        opts.context_lines = 3

        let diffError = git_diff_tree_to_workdir_with_index(&diff, ptr, tree, &opts)
        guard diffError == 0, let d = diff else {
            throw Libgit2Error.from(diffError, context: "diff tree to workdir")
        }
        defer { git_diff_free(d) }

        return formatDiffAsUnified(d)
    }

    /// Get unified diff string for staged changes only
    func diffStagedUnified() throws -> String {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var tree: OpaquePointer? = nil
        var head: OpaquePointer?
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

        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        opts.context_lines = 3

        let diffError = git_diff_tree_to_index(&diff, ptr, tree, nil, &opts)
        guard diffError == 0, let d = diff else {
            throw Libgit2Error.from(diffError, context: "diff tree to index")
        }
        defer { git_diff_free(d) }

        return formatDiffAsUnified(d)
    }

    /// Get unified diff string for unstaged changes only
    func diffUnstagedUnified() throws -> String {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        opts.flags = UInt32(GIT_DIFF_INCLUDE_UNTRACKED.rawValue)
        opts.context_lines = 3

        let diffError = git_diff_index_to_workdir(&diff, ptr, nil, &opts)
        guard diffError == 0, let d = diff else {
            throw Libgit2Error.from(diffError, context: "diff index to workdir")
        }
        defer { git_diff_free(d) }

        return formatDiffAsUnified(d)
    }

    /// Format libgit2 diff as unified diff string
    private func formatDiffAsUnified(_ diff: OpaquePointer) -> String {
        var output = ""
        let maxBytes = 4_000_000
        var bytesWritten = 0

        let numDeltas = git_diff_num_deltas(diff)
        for i in 0..<numDeltas {
            var patch: OpaquePointer?
            guard git_patch_from_diff(&patch, diff, i) == 0, let p = patch else {
                continue
            }
            defer { git_patch_free(p) }

            var buf = git_buf()
            defer { git_buf_dispose(&buf) }

            if git_patch_to_buf(&buf, p) == 0, let ptr = buf.ptr {
                let remaining = maxBytes - bytesWritten
                if remaining <= 0 {
                    output += "\n... diff truncated (too large) ...\n"
                    break
                }

                let take = min(Int(buf.size), remaining)
                let raw = UnsafeRawBufferPointer(start: ptr, count: take)
                output += String(decoding: raw, as: UTF8.self)
                bytesWritten += take

                if take < Int(buf.size) {
                    output += "\n... diff truncated (too large) ...\n"
                    break
                }
            }
        }

        return output
    }
}
