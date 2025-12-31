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

    /// List all worktrees in the repository
    func listWorktrees() throws -> [Libgit2WorktreeInfo] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var strarray = git_strarray()
        defer { git_strarray_free(&strarray) }

        let error = git_worktree_list(&strarray, ptr)
        guard error == 0 else {
            throw Libgit2Error.from(error, context: "worktree list")
        }

        var result: [Libgit2WorktreeInfo] = []

        // Add main worktree first
        if let workdir = self.workdir {
            let mainBranch = try? currentBranchName()
            // Remove only trailing slash, keep leading slash
            var normalizedPath = workdir
            while normalizedPath.hasSuffix("/") {
                normalizedPath = String(normalizedPath.dropLast())
            }
            result.append(Libgit2WorktreeInfo(
                name: "",
                path: normalizedPath,
                isLocked: false,
                isValid: true,
                branch: mainBranch
            ))
        }

        // Add linked worktrees
        for i in 0..<strarray.count {
            guard let namePtr = strarray.strings[i] else { continue }
            let name = String(cString: namePtr)

            var wt: OpaquePointer?
            guard git_worktree_lookup(&wt, ptr, name) == 0, let worktree = wt else {
                continue
            }
            defer { git_worktree_free(worktree) }

            var wtPath: String
            if let pathPtr = git_worktree_path(worktree) {
                wtPath = String(cString: pathPtr)
            } else {
                continue
            }

            // Normalize path - remove trailing slash
            while wtPath.hasSuffix("/") {
                wtPath = String(wtPath.dropLast())
            }

            let isValid = git_worktree_validate(worktree) == 0
            let isLocked = git_worktree_is_locked(nil, worktree) > 0

            // Get branch for this worktree
            var branch: String? = nil
            if isValid {
                branch = try? getWorktreeBranch(name: name)
            }

            result.append(Libgit2WorktreeInfo(
                name: name,
                path: wtPath,
                isLocked: isLocked,
                isValid: isValid,
                branch: branch
            ))
        }

        return result
    }

    /// Get branch name for a worktree
    private func getWorktreeBranch(name: String) throws -> String? {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var wt: OpaquePointer?
        let lookupError = git_worktree_lookup(&wt, ptr, name)
        guard lookupError == 0, let worktree = wt else {
            throw Libgit2Error.from(lookupError, context: "worktree lookup")
        }
        defer { git_worktree_free(worktree) }

        guard let wtPath = git_worktree_path(worktree) else {
            return nil
        }

        // Open the worktree as a repository to get its HEAD
        var wtRepo: OpaquePointer?
        let openError = git_repository_open(&wtRepo, String(cString: wtPath))
        guard openError == 0, let repo = wtRepo else {
            return nil
        }
        defer { git_repository_free(repo) }

        var head: OpaquePointer?
        let headError = git_repository_head(&head, repo)
        guard headError == 0, let ref = head else {
            return nil
        }
        defer { git_reference_free(ref) }

        guard let shorthand = git_reference_shorthand(ref) else {
            return nil
        }
        return String(cString: shorthand)
    }

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

    /// Validate a worktree
    func validateWorktree(name: String) throws -> Bool {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var wt: OpaquePointer?
        let lookupError = git_worktree_lookup(&wt, ptr, name)
        guard lookupError == 0, let worktree = wt else {
            throw Libgit2Error.worktreeNotFound(name)
        }
        defer { git_worktree_free(worktree) }

        return git_worktree_validate(worktree) == 0
    }
}
