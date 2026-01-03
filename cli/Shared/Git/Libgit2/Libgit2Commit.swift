import Foundation
import Clibgit2

/// Commit information
nonisolated struct Libgit2CommitInfo: Sendable {
    let oid: String
    let shortOid: String
    let message: String
    let summary: String
    let author: Libgit2Signature
    let committer: Libgit2Signature
    let parentCount: Int
    let time: Date
}

/// Signature (author/committer)
nonisolated struct Libgit2Signature: Sendable {
    let name: String
    let email: String
    let time: Date
}

/// Commit operations extension for Libgit2Repository
nonisolated extension Libgit2Repository {

    /// Create a new commit
    func commit(message: String, amend: Bool = false) throws -> String {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        let index = try getIndex()
        defer { git_index_free(index) }

        // Check if there are staged changes
        if git_index_entrycount(index) == 0 && !amend {
            throw Libgit2Error.indexError("Nothing to commit")
        }

        // Write index to tree
        var treeOid = git_oid()
        let writeError = git_index_write_tree(&treeOid, index)
        guard writeError == 0 else {
            throw Libgit2Error.from(writeError, context: "write tree")
        }

        var tree: OpaquePointer?
        let treeLookupError = git_tree_lookup(&tree, ptr, &treeOid)
        guard treeLookupError == 0, let t = tree else {
            throw Libgit2Error.from(treeLookupError, context: "tree lookup")
        }
        defer { git_tree_free(t) }

        // Get signature
        let sig = try defaultSignature()
        defer { git_signature_free(sig) }

        var commitOid = git_oid()

        if amend {
            // Amend last commit
            let headRef = try head()
            defer { git_reference_free(headRef) }

            var headCommit: OpaquePointer?
            let peelError = git_reference_peel(&headCommit, headRef, GIT_OBJECT_COMMIT)
            guard peelError == 0, let hc = headCommit else {
                throw Libgit2Error.from(peelError, context: "peel HEAD")
            }
            defer { git_commit_free(hc) }

            let amendError = git_commit_amend(
                &commitOid,
                hc,
                "HEAD",
                nil,  // Keep original author
                sig,
                nil,
                message,
                t
            )
            guard amendError == 0 else {
                throw Libgit2Error.from(amendError, context: "amend commit")
            }
        } else {
            // Create new commit
            var parents: [OpaquePointer?] = []
            var parentCount = 0

            // Get parent commit (HEAD) if exists
            var headRef: OpaquePointer?
            if git_repository_head(&headRef, ptr) == 0, let h = headRef {
                defer { git_reference_free(h) }

                var headCommit: OpaquePointer?
                if git_reference_peel(&headCommit, h, GIT_OBJECT_COMMIT) == 0, let hc = headCommit {
                    parents.append(hc)
                    parentCount = 1
                }
            }
            defer { parents.compactMap { $0 }.forEach { git_commit_free($0) } }

            let commitError: Int32
            if parentCount > 0 {
                commitError = parents.withUnsafeMutableBufferPointer { buffer in
                    git_commit_create(
                        &commitOid,
                        ptr,
                        "HEAD",
                        sig,
                        sig,
                        nil,
                        message,
                        t,
                        1,
                        buffer.baseAddress
                    )
                }
            } else {
                // Initial commit (no parents)
                commitError = git_commit_create(
                    &commitOid,
                    ptr,
                    "HEAD",
                    sig,
                    sig,
                    nil,
                    message,
                    t,
                    0,
                    nil
                )
            }

            guard commitError == 0 else {
                throw Libgit2Error.from(commitError, context: "create commit")
            }
        }

        // Return commit hash
        var oidStr = [CChar](repeating: 0, count: 41)
        git_oid_tostr(&oidStr, 41, &commitOid)
        return String(cString: oidStr)
    }

    /// Get commit log
    func log(limit: Int = 50, skip: Int = 0) throws -> [Libgit2CommitInfo] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var revwalk: OpaquePointer?
        let walkError = git_revwalk_new(&revwalk, ptr)
        guard walkError == 0, let walk = revwalk else {
            throw Libgit2Error.from(walkError, context: "revwalk new")
        }
        defer { git_revwalk_free(walk) }

        // Sort by time, newest first
        git_revwalk_sorting(walk, UInt32(GIT_SORT_TIME.rawValue))

        // Push HEAD
        let pushError = git_revwalk_push_head(walk)
        guard pushError == 0 else {
            // No HEAD - empty repo
            return []
        }

        var result: [Libgit2CommitInfo] = []
        var oid = git_oid()
        var skipped = 0

        while git_revwalk_next(&oid, walk) == 0 {
            // Skip entries
            if skipped < skip {
                skipped += 1
                continue
            }

            // Limit entries
            if result.count >= limit {
                break
            }

            var commit: OpaquePointer?
            guard git_commit_lookup(&commit, ptr, &oid) == 0, let c = commit else {
                continue
            }
            defer { git_commit_free(c) }

            result.append(parseCommit(c, oid: &oid))
        }

        return result
    }

    /// Get a specific commit by hash
    func getCommit(_ hash: String) throws -> Libgit2CommitInfo {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var oid = git_oid()
        let parseError = git_oid_fromstr(&oid, hash)
        guard parseError == 0 else {
            throw Libgit2Error.from(parseError, context: "parse oid")
        }

        var commit: OpaquePointer?
        let lookupError = git_commit_lookup(&commit, ptr, &oid)
        guard lookupError == 0, let c = commit else {
            throw Libgit2Error.from(lookupError, context: "commit lookup")
        }
        defer { git_commit_free(c) }

        return parseCommit(c, oid: &oid)
    }

    /// Get commit stats (files changed, insertions, deletions)
    func commitStats(_ hash: String) throws -> Libgit2DiffStats {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var oid = git_oid()
        let parseError = git_oid_fromstr(&oid, hash)
        guard parseError == 0 else {
            throw Libgit2Error.from(parseError, context: "parse oid")
        }

        var commit: OpaquePointer?
        let lookupError = git_commit_lookup(&commit, ptr, &oid)
        guard lookupError == 0, let c = commit else {
            throw Libgit2Error.from(lookupError, context: "commit lookup")
        }
        defer { git_commit_free(c) }

        // Get commit tree
        var tree: OpaquePointer?
        let treeError = git_commit_tree(&tree, c)
        guard treeError == 0, let t = tree else {
            throw Libgit2Error.from(treeError, context: "commit tree")
        }
        defer { git_tree_free(t) }

        // Get parent tree (if exists)
        var parentTree: OpaquePointer? = nil
        if git_commit_parentcount(c) > 0 {
            var parent: OpaquePointer?
            if git_commit_parent(&parent, c, 0) == 0, let p = parent {
                defer { git_commit_free(p) }
                var pt: OpaquePointer?
                if git_commit_tree(&pt, p) == 0 {
                    parentTree = pt
                }
            }
        }
        defer { if let pt = parentTree { git_tree_free(pt) } }

        // Get diff
        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))

        let diffError = git_diff_tree_to_tree(&diff, ptr, parentTree, t, &opts)
        guard diffError == 0, let d = diff else {
            throw Libgit2Error.from(diffError, context: "diff tree to tree")
        }
        defer { git_diff_free(d) }

        var stats: OpaquePointer?
        let statsError = git_diff_get_stats(&stats, d)
        guard statsError == 0, let s = stats else {
            throw Libgit2Error.from(statsError, context: "diff stats")
        }
        defer { git_diff_stats_free(s) }

        return Libgit2DiffStats(
            filesChanged: git_diff_stats_files_changed(s),
            insertions: git_diff_stats_insertions(s),
            deletions: git_diff_stats_deletions(s)
        )
    }

    /// Reset to a specific commit
    func reset(to target: String, type: ResetType = .mixed) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var obj: OpaquePointer?
        let revparseError = git_revparse_single(&obj, ptr, target)
        guard revparseError == 0, let object = obj else {
            throw Libgit2Error.from(revparseError, context: "revparse")
        }
        defer { git_object_free(object) }

        var commit: OpaquePointer?
        let peelError = git_object_peel(&commit, object, GIT_OBJECT_COMMIT)
        guard peelError == 0, let c = commit else {
            throw Libgit2Error.from(peelError, context: "peel to commit")
        }
        defer { git_commit_free(c) }

        var opts = git_checkout_options()
        git_checkout_options_init(&opts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))

        let resetType: git_reset_t
        switch type {
        case .soft:
            resetType = GIT_RESET_SOFT
        case .mixed:
            resetType = GIT_RESET_MIXED
        case .hard:
            resetType = GIT_RESET_HARD
            opts.checkout_strategy = UInt32(GIT_CHECKOUT_FORCE.rawValue)
        }

        let resetError = git_reset(ptr, c, resetType, &opts)
        guard resetError == 0 else {
            throw Libgit2Error.from(resetError, context: "reset")
        }
    }

    enum ResetType {
        case soft   // Only move HEAD
        case mixed  // Move HEAD and reset index
        case hard   // Move HEAD, reset index and working directory
    }

    // MARK: - Private Helpers

    private func parseCommit(_ commit: OpaquePointer, oid: inout git_oid) -> Libgit2CommitInfo {
        // Get OID string
        var oidStr = [CChar](repeating: 0, count: 41)
        git_oid_tostr(&oidStr, 41, &oid)
        let fullOid = String(cString: oidStr)

        var shortOidStr = [CChar](repeating: 0, count: 8)
        git_oid_tostr(&shortOidStr, 8, &oid)
        let shortOid = String(cString: shortOidStr)

        // Get message
        let message = git_commit_message(commit).map { String(cString: $0) } ?? ""
        let summary = git_commit_summary(commit).map { String(cString: $0) } ?? ""

        // Get author
        let authorSig = git_commit_author(commit)
        let author = parseSignature(authorSig)

        // Get committer
        let committerSig = git_commit_committer(commit)
        let committer = parseSignature(committerSig)

        // Get parent count
        let parentCount = Int(git_commit_parentcount(commit))

        // Get time
        let timestamp = git_commit_time(commit)
        let time = Date(timeIntervalSince1970: TimeInterval(timestamp))

        return Libgit2CommitInfo(
            oid: fullOid,
            shortOid: shortOid,
            message: message,
            summary: summary,
            author: author,
            committer: committer,
            parentCount: parentCount,
            time: time
        )
    }

    private func parseSignature(_ sig: UnsafePointer<git_signature>?) -> Libgit2Signature {
        guard let s = sig else {
            return Libgit2Signature(name: "Unknown", email: "", time: Date())
        }

        let name = s.pointee.name.map { String(cString: $0) } ?? "Unknown"
        let email = s.pointee.email.map { String(cString: $0) } ?? ""
        let time = Date(timeIntervalSince1970: TimeInterval(s.pointee.when.time))

        return Libgit2Signature(name: name, email: email, time: time)
    }
}
