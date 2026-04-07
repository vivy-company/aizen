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
}
