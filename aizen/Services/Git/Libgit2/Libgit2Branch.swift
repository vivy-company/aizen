import Foundation
import Clibgit2

/// Branch type
enum Libgit2BranchType {
    case local
    case remote
    case all

    var gitType: git_branch_t {
        switch self {
        case .local: return GIT_BRANCH_LOCAL
        case .remote: return GIT_BRANCH_REMOTE
        case .all: return GIT_BRANCH_ALL
        }
    }
}

/// Branch information
struct Libgit2BranchInfo: Sendable {
    let name: String
    let fullName: String
    let isRemote: Bool
    let isHead: Bool
    let upstream: String?
    let aheadBehind: (ahead: Int, behind: Int)?
}

/// Branch operations extension for Libgit2Repository
extension Libgit2Repository {

    /// List all branches
    func listBranches(type: Libgit2BranchType = .all, includeUpstreamInfo: Bool = false) throws -> [Libgit2BranchInfo] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var iterator: OpaquePointer?
        let iterError = git_branch_iterator_new(&iterator, ptr, type.gitType)
        guard iterError == 0, let iter = iterator else {
            throw Libgit2Error.from(iterError, context: "branch iterator")
        }
        defer { git_branch_iterator_free(iter) }

        var result: [Libgit2BranchInfo] = []
        var ref: OpaquePointer?
        var branchType: git_branch_t = GIT_BRANCH_LOCAL

        while git_branch_next(&ref, &branchType, iter) == 0 {
            guard let reference = ref else { continue }
            defer { git_reference_free(reference) }

            guard let namePtr = git_reference_shorthand(reference) else { continue }
            let name = String(cString: namePtr)

            guard let fullNamePtr = git_reference_name(reference) else { continue }
            let fullName = String(cString: fullNamePtr)

            let isRemote = branchType == GIT_BRANCH_REMOTE
            let isHead = git_branch_is_head(reference) != 0

            // Get upstream if local branch
            var upstream: String? = nil
            var aheadBehind: (ahead: Int, behind: Int)? = nil

            if includeUpstreamInfo, !isRemote {
                var upstreamRef: OpaquePointer?
                if git_branch_upstream(&upstreamRef, reference) == 0, let ur = upstreamRef {
                    defer { git_reference_free(ur) }
                    if let upstreamName = git_reference_shorthand(ur) {
                        upstream = String(cString: upstreamName)
                    }

                    // Calculate ahead/behind
                    var localOid = git_oid()
                    var upstreamOid = git_oid()

                    if git_reference_name_to_id(&localOid, ptr, fullName) == 0,
                       let urName = git_reference_name(ur),
                       git_reference_name_to_id(&upstreamOid, ptr, urName) == 0 {
                        var ahead: Int = 0
                        var behind: Int = 0
                        if git_graph_ahead_behind(&ahead, &behind, ptr, &localOid, &upstreamOid) == 0 {
                            aheadBehind = (ahead, behind)
                        }
                    }
                }
            }

            result.append(Libgit2BranchInfo(
                name: name,
                fullName: fullName,
                isRemote: isRemote,
                isHead: isHead,
                upstream: upstream,
                aheadBehind: aheadBehind
            ))
        }

        return result
    }

    func shortOid(forReferenceFullName fullName: String) throws -> String {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var oid = git_oid()
        let err = git_reference_name_to_id(&oid, ptr, fullName)
        guard err == 0 else {
            throw Libgit2Error.from(err, context: "reference name to id")
        }

        var buffer = [CChar](repeating: 0, count: Int(GIT_OID_HEXSZ) + 1)
        _ = buffer.withUnsafeMutableBufferPointer { buf in
            git_oid_tostr(buf.baseAddress, buf.count, &oid)
        }
        let hex = String(cString: buffer)
        return String(hex.prefix(7))
    }

    /// Calculate ahead/behind for the current HEAD's upstream (fast path).
    /// Returns (0, 0) if HEAD is detached or no upstream is configured.
    func headAheadBehind() throws -> (ahead: Int, behind: Int) {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        guard git_repository_head_detached(ptr) == 0 else {
            return (0, 0)
        }

        var headRef: OpaquePointer?
        let headError = git_repository_head(&headRef, ptr)
        guard headError == 0, let head = headRef else {
            return (0, 0)
        }
        defer { git_reference_free(head) }

        var upstreamRef: OpaquePointer?
        let upstreamError = git_branch_upstream(&upstreamRef, head)
        guard upstreamError == 0, let upstream = upstreamRef else {
            return (0, 0)
        }
        defer { git_reference_free(upstream) }

        guard let headFullName = git_reference_name(head),
              let upstreamFullName = git_reference_name(upstream) else {
            return (0, 0)
        }

        var localOid = git_oid()
        var upstreamOid = git_oid()

        guard git_reference_name_to_id(&localOid, ptr, headFullName) == 0,
              git_reference_name_to_id(&upstreamOid, ptr, upstreamFullName) == 0 else {
            return (0, 0)
        }

        var ahead: Int = 0
        var behind: Int = 0
        guard git_graph_ahead_behind(&ahead, &behind, ptr, &localOid, &upstreamOid) == 0 else {
            return (0, 0)
        }

        return (ahead, behind)
    }

    /// Create a new branch
    func createBranch(name: String, from target: String? = nil, force: Bool = false) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        // Get target commit
        var commit: OpaquePointer?

        if let targetRef = target {
            // Resolve target reference to commit
            var obj: OpaquePointer?
            let revparseError = git_revparse_single(&obj, ptr, targetRef)
            guard revparseError == 0, let object = obj else {
                throw Libgit2Error.referenceNotFound(targetRef)
            }

            // Peel to commit if needed
            if git_object_type(object) != GIT_OBJECT_COMMIT {
                var peeled: OpaquePointer?
                let peelError = git_object_peel(&peeled, object, GIT_OBJECT_COMMIT)
                git_object_free(object)
                guard peelError == 0, let p = peeled else {
                    throw Libgit2Error.from(peelError, context: "peel to commit")
                }
                commit = p
            } else {
                commit = object
            }
        } else {
            // Use HEAD
            var head: OpaquePointer?
            let headError = git_repository_head(&head, ptr)
            guard headError == 0, let h = head else {
                throw Libgit2Error.from(headError, context: "get HEAD")
            }
            defer { git_reference_free(h) }

            var peeled: OpaquePointer?
            let peelError = git_reference_peel(&peeled, h, GIT_OBJECT_COMMIT)
            guard peelError == 0, let p = peeled else {
                throw Libgit2Error.from(peelError, context: "peel HEAD to commit")
            }
            commit = p
        }

        guard let targetCommit = commit else {
            throw Libgit2Error.referenceNotFound(target ?? "HEAD")
        }
        defer { git_commit_free(targetCommit) }

        var branch: OpaquePointer?
        let createError = git_branch_create(&branch, ptr, name, targetCommit, force ? 1 : 0)
        defer { if let b = branch { git_reference_free(b) } }

        guard createError == 0 else {
            if createError == Int32(GIT_EEXISTS.rawValue) {
                throw Libgit2Error.branchAlreadyExists(name)
            }
            throw Libgit2Error.from(createError, context: "branch create")
        }
    }

    /// Delete a branch
    func deleteBranch(name: String, force: Bool = false) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var branch: OpaquePointer?
        let lookupError = git_branch_lookup(&branch, ptr, name, GIT_BRANCH_LOCAL)
        guard lookupError == 0, let b = branch else {
            throw Libgit2Error.branchNotFound(name)
        }
        defer { git_reference_free(b) }

        // Check if it's the current branch
        if git_branch_is_head(b) != 0 {
            throw Libgit2Error.checkoutError("Cannot delete the currently checked out branch")
        }

        let deleteError = git_branch_delete(b)
        guard deleteError == 0 else {
            throw Libgit2Error.from(deleteError, context: "branch delete")
        }
    }

    /// Checkout a branch
    func checkoutBranch(name: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        // Try local branch first
        var branch: OpaquePointer?
        var lookupError = git_branch_lookup(&branch, ptr, name, GIT_BRANCH_LOCAL)

        if lookupError != 0 {
            // Try remote branch
            lookupError = git_branch_lookup(&branch, ptr, name, GIT_BRANCH_REMOTE)
        }

        guard lookupError == 0, let b = branch else {
            throw Libgit2Error.branchNotFound(name)
        }
        defer { git_reference_free(b) }

        // Get commit for the branch
        var commit: OpaquePointer?
        let peelError = git_reference_peel(&commit, b, GIT_OBJECT_COMMIT)
        guard peelError == 0, let c = commit else {
            throw Libgit2Error.from(peelError, context: "peel branch to commit")
        }
        defer { git_object_free(c) }

        // Get tree from commit
        var tree: OpaquePointer?
        let treeError = git_commit_tree(&tree, c)
        guard treeError == 0, let t = tree else {
            throw Libgit2Error.from(treeError, context: "get commit tree")
        }
        defer { git_tree_free(t) }

        // Checkout
        var opts = git_checkout_options()
        git_checkout_options_init(&opts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        opts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)

        let checkoutError = git_checkout_tree(ptr, t, &opts)
        guard checkoutError == 0 else {
            if checkoutError == Int32(GIT_ECONFLICT.rawValue) {
                throw Libgit2Error.uncommittedChanges("Checkout would overwrite uncommitted changes")
            }
            throw Libgit2Error.from(checkoutError, context: "checkout tree")
        }

        // Update HEAD
        guard let refName = git_reference_name(b) else {
            throw Libgit2Error.referenceNotFound(name)
        }

        let setHeadError = git_repository_set_head(ptr, refName)
        guard setHeadError == 0 else {
            throw Libgit2Error.from(setHeadError, context: "set HEAD")
        }
    }

    /// Rename a branch
    func renameBranch(oldName: String, newName: String, force: Bool = false) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var branch: OpaquePointer?
        let lookupError = git_branch_lookup(&branch, ptr, oldName, GIT_BRANCH_LOCAL)
        guard lookupError == 0, let b = branch else {
            throw Libgit2Error.branchNotFound(oldName)
        }
        defer { git_reference_free(b) }

        var newBranch: OpaquePointer?
        let moveError = git_branch_move(&newBranch, b, newName, force ? 1 : 0)
        defer { if let nb = newBranch { git_reference_free(nb) } }

        guard moveError == 0 else {
            if moveError == Int32(GIT_EEXISTS.rawValue) {
                throw Libgit2Error.branchAlreadyExists(newName)
            }
            throw Libgit2Error.from(moveError, context: "branch rename")
        }
    }

    /// Set upstream for a branch
    func setUpstream(branch: String, upstream: String?) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var branchRef: OpaquePointer?
        let lookupError = git_branch_lookup(&branchRef, ptr, branch, GIT_BRANCH_LOCAL)
        guard lookupError == 0, let b = branchRef else {
            throw Libgit2Error.branchNotFound(branch)
        }
        defer { git_reference_free(b) }

        let setError = git_branch_set_upstream(b, upstream)
        guard setError == 0 else {
            throw Libgit2Error.from(setError, context: "set upstream")
        }
    }
}
