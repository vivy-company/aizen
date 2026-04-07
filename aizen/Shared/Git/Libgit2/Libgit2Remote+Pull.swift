import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {

    /// Pull from remote (fetch + merge)
    func pull(remoteName: String = "origin") throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        try fetch(remoteName: remoteName)

        guard let branchName = try currentBranchName() else {
            throw Libgit2Error.referenceNotFound("HEAD")
        }

        let trackingRef = "refs/remotes/\(remoteName)/\(branchName)"
        var remoteRef: OpaquePointer?
        let lookupError = git_reference_lookup(&remoteRef, ptr, trackingRef)
        guard lookupError == 0, let rRef = remoteRef else {
            return
        }
        defer { git_reference_free(rRef) }

        var annotatedCommit: OpaquePointer?
        let annotateError = git_annotated_commit_from_ref(&annotatedCommit, ptr, rRef)
        guard annotateError == 0, let ac = annotatedCommit else {
            throw Libgit2Error.from(annotateError, context: "annotated commit")
        }
        defer { git_annotated_commit_free(ac) }

        var analysis: git_merge_analysis_t = GIT_MERGE_ANALYSIS_NONE
        var preference: git_merge_preference_t = GIT_MERGE_PREFERENCE_NONE

        var commits: [OpaquePointer?] = [ac]
        let analysisError = commits.withUnsafeMutableBufferPointer { buffer in
            git_merge_analysis(&analysis, &preference, ptr, buffer.baseAddress, 1)
        }
        guard analysisError == 0 else {
            throw Libgit2Error.from(analysisError, context: "merge analysis")
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue != 0 {
            return
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue != 0 {
            var targetOid = git_oid()
            let oidError = git_reference_name_to_id(&targetOid, ptr, trackingRef)
            guard oidError == 0 else {
                throw Libgit2Error.from(oidError, context: "get target oid")
            }

            var targetCommit: OpaquePointer?
            let commitError = git_commit_lookup(&targetCommit, ptr, &targetOid)
            guard commitError == 0, let tc = targetCommit else {
                throw Libgit2Error.from(commitError, context: "commit lookup")
            }
            defer { git_commit_free(tc) }

            var checkoutOpts = git_checkout_options()
            git_checkout_options_init(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
            checkoutOpts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)

            var tree: OpaquePointer?
            let treeError = git_commit_tree(&tree, tc)
            guard treeError == 0, let t = tree else {
                throw Libgit2Error.from(treeError, context: "get commit tree")
            }
            defer { git_tree_free(t) }

            let checkoutError = git_checkout_tree(ptr, t, &checkoutOpts)
            guard checkoutError == 0 else {
                throw Libgit2Error.from(checkoutError, context: "checkout tree")
            }

            var newRef: OpaquePointer?
            let refError = git_reference_set_target(&newRef, try head(), &targetOid, "pull: fast-forward")
            defer { if let r = newRef { git_reference_free(r) } }
            guard refError == 0 else {
                throw Libgit2Error.from(refError, context: "update HEAD")
            }
        } else if analysis.rawValue & GIT_MERGE_ANALYSIS_NORMAL.rawValue != 0 {
            var mergeOpts = git_merge_options()
            git_merge_options_init(&mergeOpts, UInt32(GIT_MERGE_OPTIONS_VERSION))

            var checkoutOpts = git_checkout_options()
            git_checkout_options_init(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
            checkoutOpts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)

            var commits: [OpaquePointer?] = [ac]
            let mergeError = commits.withUnsafeMutableBufferPointer { buffer in
                git_merge(ptr, buffer.baseAddress, 1, &mergeOpts, &checkoutOpts)
            }

            if mergeError != 0 {
                if mergeError == Int32(GIT_ECONFLICT.rawValue) || mergeError == Int32(GIT_EMERGECONFLICT.rawValue) {
                    throw Libgit2Error.mergeConflict("Merge conflicts detected. Please resolve manually.")
                }
                throw Libgit2Error.from(mergeError, context: "merge")
            }

            let index = try getIndex()
            defer { git_index_free(index) }

            if git_index_has_conflicts(index) != 0 {
                throw Libgit2Error.mergeConflict("Merge conflicts detected. Please resolve manually.")
            }

            try createMergeCommit(remoteBranch: "\(remoteName)/\(branchName)")
        }
    }

    private func createMergeCommit(remoteBranch: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        let index = try getIndex()
        defer { git_index_free(index) }

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

        let headRef = try head()
        defer { git_reference_free(headRef) }

        var headCommit: OpaquePointer?
        let peelError = git_reference_peel(&headCommit, headRef, GIT_OBJECT_COMMIT)
        guard peelError == 0, let hc = headCommit else {
            throw Libgit2Error.from(peelError, context: "peel HEAD")
        }
        defer { git_commit_free(hc) }

        var mergeHeadOid = git_oid()
        let mergeHeadPath = (gitdir ?? "") + "MERGE_HEAD"
        let content = try? String(contentsOfFile: mergeHeadPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let oidString = content, git_oid_fromstr(&mergeHeadOid, oidString) == 0 else {
            throw Libgit2Error.referenceNotFound("MERGE_HEAD")
        }

        var mergeCommit: OpaquePointer?
        let mergeLookupError = git_commit_lookup(&mergeCommit, ptr, &mergeHeadOid)
        guard mergeLookupError == 0, let mc = mergeCommit else {
            throw Libgit2Error.from(mergeLookupError, context: "merge commit lookup")
        }
        defer { git_commit_free(mc) }

        let sig = try defaultSignature()
        defer { git_signature_free(sig) }

        let message = "Merge remote-tracking branch '\(remoteBranch)'"
        var commitOid = git_oid()
        var parents: [OpaquePointer?] = [hc, mc]

        let commitError = parents.withUnsafeMutableBufferPointer { buffer in
            git_commit_create(
                &commitOid,
                ptr,
                "HEAD",
                sig,
                sig,
                nil,
                message,
                t,
                2,
                buffer.baseAddress
            )
        }

        guard commitError == 0 else {
            throw Libgit2Error.from(commitError, context: "create commit")
        }

        git_repository_state_cleanup(ptr)
    }
}
