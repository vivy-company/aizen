import Foundation
import Clibgit2

/// Worktree information
nonisolated struct Libgit2WorktreeInfo: Sendable {
    let name: String
    let path: String
    let isLocked: Bool
    let isValid: Bool
    let branch: String?

    /// Whether this is the main worktree
    var isMain: Bool {
        name.isEmpty
    }
}

/// Worktree operations extension for Libgit2Repository
nonisolated extension Libgit2Repository {

    /// Add a new worktree
    func addWorktree(name: String, path: String, branch: String? = nil, createBranch: Bool = false, baseBranch: String? = nil) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var opts = git_worktree_add_options()
        git_worktree_add_options_init(&opts, UInt32(GIT_WORKTREE_ADD_OPTIONS_VERSION))

        // If branch specified, look up or create the reference
        var ref: OpaquePointer? = nil
        defer { if let r = ref { git_reference_free(r) } }

        if let branchName = branch {
            if createBranch {
                // Create new branch from baseBranch or HEAD
                let baseRef: OpaquePointer
                if let base = baseBranch {
                    var lookupRef: OpaquePointer?
                    let refName = "refs/heads/\(base)"
                    let lookupError = git_reference_lookup(&lookupRef, ptr, refName)
                    guard lookupError == 0, let r = lookupRef else {
                        throw Libgit2Error.branchNotFound(base)
                    }
                    baseRef = r
                } else {
                    var headRef: OpaquePointer?
                    let headError = git_repository_head(&headRef, ptr)
                    guard headError == 0, let r = headRef else {
                        throw Libgit2Error.from(headError, context: "get HEAD for branch creation")
                    }
                    baseRef = r
                }
                defer { git_reference_free(baseRef) }

                // Get commit from reference
                var commit: OpaquePointer?
                let peelError = git_reference_peel(&commit, baseRef, GIT_OBJECT_COMMIT)
                guard peelError == 0, let c = commit else {
                    throw Libgit2Error.from(peelError, context: "peel reference to commit")
                }
                defer { git_commit_free(c) }

                // Create the branch
                var newBranch: OpaquePointer?
                let createError = git_branch_create(&newBranch, ptr, branchName, c, 0)
                guard createError == 0, let b = newBranch else {
                    if createError == Int32(GIT_EEXISTS.rawValue) {
                        throw Libgit2Error.branchAlreadyExists(branchName)
                    }
                    throw Libgit2Error.from(createError, context: "branch create")
                }
                ref = b
            } else {
                // Use existing branch
                var lookupRef: OpaquePointer?
                let refName = "refs/heads/\(branchName)"
                let lookupError = git_reference_lookup(&lookupRef, ptr, refName)
                guard lookupError == 0, let r = lookupRef else {
                    throw Libgit2Error.branchNotFound(branchName)
                }
                ref = r
            }
            opts.ref = ref
        }

        var wt: OpaquePointer?
        let error = git_worktree_add(&wt, ptr, name, path, &opts)
        defer { if let w = wt { git_worktree_free(w) } }

        guard error == 0 else {
            if error == Int32(GIT_EEXISTS.rawValue) {
                throw Libgit2Error.worktreeAlreadyExists(name)
            }
            throw Libgit2Error.from(error, context: "worktree add")
        }
    }

    /// Remove a worktree
    func removeWorktree(name: String, force: Bool = false) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var wt: OpaquePointer?
        let lookupError = git_worktree_lookup(&wt, ptr, name)
        guard lookupError == 0, let worktree = wt else {
            throw Libgit2Error.worktreeNotFound(name)
        }
        defer { git_worktree_free(worktree) }

        var opts = git_worktree_prune_options()
        git_worktree_prune_options_init(&opts, UInt32(GIT_WORKTREE_PRUNE_OPTIONS_VERSION))

        // GIT_WORKTREE_PRUNE_VALID is required to prune valid working trees
        // GIT_WORKTREE_PRUNE_WORKING_TREE removes the working tree directory
        // GIT_WORKTREE_PRUNE_LOCKED is only used with force to remove locked worktrees
        if force {
            opts.flags = UInt32(GIT_WORKTREE_PRUNE_WORKING_TREE.rawValue) | UInt32(GIT_WORKTREE_PRUNE_VALID.rawValue) | UInt32(GIT_WORKTREE_PRUNE_LOCKED.rawValue)
        } else {
            opts.flags = UInt32(GIT_WORKTREE_PRUNE_WORKING_TREE.rawValue) | UInt32(GIT_WORKTREE_PRUNE_VALID.rawValue)
        }

        // Check if prunable
        let isPrunable = git_worktree_is_prunable(worktree, &opts)
        guard isPrunable > 0 else {
            if git_worktree_is_locked(nil, worktree) > 0 {
                throw Libgit2Error.worktreeLocked(name)
            }
            throw Libgit2Error.from(Int32(isPrunable), context: "worktree is_prunable")
        }

        let pruneError = git_worktree_prune(worktree, &opts)
        guard pruneError == 0 else {
            throw Libgit2Error.from(pruneError, context: "worktree prune")
        }
    }

    /// Lock a worktree
    func lockWorktree(name: String, reason: String? = nil) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var wt: OpaquePointer?
        let lookupError = git_worktree_lookup(&wt, ptr, name)
        guard lookupError == 0, let worktree = wt else {
            throw Libgit2Error.worktreeNotFound(name)
        }
        defer { git_worktree_free(worktree) }

        let lockError = git_worktree_lock(worktree, reason)
        guard lockError == 0 else {
            throw Libgit2Error.from(lockError, context: "worktree lock")
        }
    }

    /// Unlock a worktree
    func unlockWorktree(name: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var wt: OpaquePointer?
        let lookupError = git_worktree_lookup(&wt, ptr, name)
        guard lookupError == 0, let worktree = wt else {
            throw Libgit2Error.worktreeNotFound(name)
        }
        defer { git_worktree_free(worktree) }

        let unlockError = git_worktree_unlock(worktree)
        guard unlockError >= 0 else {
            throw Libgit2Error.from(unlockError, context: "worktree unlock")
        }
    }

}
