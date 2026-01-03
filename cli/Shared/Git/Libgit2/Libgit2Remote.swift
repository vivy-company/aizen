import Foundation
import Clibgit2

/// Remote information
nonisolated struct Libgit2RemoteInfo: Sendable {
    let name: String
    let url: String?
    let pushUrl: String?
}

/// Fetch/push progress
nonisolated struct Libgit2TransferProgress: Sendable {
    let totalObjects: Int
    let indexedObjects: Int
    let receivedObjects: Int
    let localObjects: Int
    let totalDeltas: Int
    let indexedDeltas: Int
    let receivedBytes: Int

    var isComplete: Bool {
        receivedObjects == totalObjects && indexedDeltas == totalDeltas
    }

    var percentComplete: Double {
        guard totalObjects > 0 else { return 0 }
        let objectProgress = Double(receivedObjects) / Double(totalObjects)
        let deltaProgress = totalDeltas > 0 ? Double(indexedDeltas) / Double(totalDeltas) : 1.0
        return (objectProgress + deltaProgress) / 2.0 * 100.0
    }
}

/// Remote operations extension for Libgit2Repository
nonisolated extension Libgit2Repository {

    private struct SSHRemoteURLParts: Sendable {
        let isSSH: Bool
        let isSCP: Bool
        let user: String?
        let host: String
        let path: String
        let port: Int?
    }

    private func parseSSHRemoteURL(_ url: String) -> SSHRemoteURLParts? {
        if url.hasPrefix("ssh://"), let u = URL(string: url), let host = u.host {
            let user = u.user
            let port = u.port
            // URL.path includes leading /
            let path = u.path
            return SSHRemoteURLParts(isSSH: true, isSCP: false, user: user, host: host, path: path, port: port)
        }

        // SCP-like: [user@]host:path
        if !url.contains("://"), let colonIndex = url.firstIndex(of: ":") {
            let before = String(url[..<colonIndex])
            let after = String(url[url.index(after: colonIndex)...])
            guard !before.contains("/"), !after.isEmpty else { return nil }

            let user: String?
            let host: String
            if let at = before.firstIndex(of: "@") {
                user = String(before[..<at])
                host = String(before[before.index(after: at)...])
            } else {
                user = nil
                host = before
            }

            guard !host.isEmpty else { return nil }
            return SSHRemoteURLParts(isSSH: true, isSCP: true, user: user, host: host, path: after, port: nil)
        }

        return nil
    }

    private func buildResolvedSSHURL(from parts: SSHRemoteURLParts, resolution: SSHConfigResolution?) -> String? {
        guard parts.isSSH else { return nil }

        let connectHost = resolution?.hostName?.isEmpty == false ? resolution!.hostName! : parts.host
        let user = parts.user ?? resolution?.user
        let port = resolution?.port ?? parts.port

        if parts.isSCP, (port == nil || port == 22) {
            // Preserve SCP-like semantics when possible.
            let userPrefix = (user?.isEmpty == false) ? "\(user!)@" : ""
            return "\(userPrefix)\(connectHost):\(parts.path)"
        }

        // Fall back to ssh:// format (supports port)
        var components = URLComponents()
        components.scheme = "ssh"
        components.host = connectHost
        components.user = user
        components.port = port

        // Ensure leading slash for ssh:// URLs
        let path = parts.isSCP ? "/\(parts.path)" : (parts.path.hasPrefix("/") ? parts.path : "/\(parts.path)")
        components.path = path

        return components.url?.absoluteString
    }

    private func prepareSSHCallbacksPayload(originalHost: String) -> UnsafeMutablePointer<SSHCredentialPayload> {
        let payload = UnsafeMutablePointer<SSHCredentialPayload>.allocate(capacity: 1)
        let hostDup = strdup(originalHost)
        payload.initialize(to: SSHCredentialPayload(keyHost: hostDup))
        return payload
    }

    private func freeSSHCallbacksPayload(_ payload: UnsafeMutablePointer<SSHCredentialPayload>?) {
        guard let payload else { return }
        if let host = payload.pointee.keyHost {
            free(host)
        }
        payload.deinitialize(count: 1)
        payload.deallocate()
    }

    private func configureRemoteInstanceURLIfNeeded(remote: OpaquePointer, forPush: Bool) -> UnsafeMutablePointer<SSHCredentialPayload>? {
        let rawURLPtr = forPush ? git_remote_pushurl(remote) : git_remote_url(remote)
        guard let rawURLPtr else { return nil }
        let rawURL = String(cString: rawURLPtr)

        guard let parts = parseSSHRemoteURL(rawURL) else { return nil }

        let resolution = resolveSSHConfig(forHost: parts.host)
        let resolvedURL = buildResolvedSSHURL(from: parts, resolution: resolution)

        if let resolvedURL, resolvedURL != rawURL {
            resolvedURL.withCString { cStr in
                if forPush {
                    _ = git_remote_set_instance_pushurl(remote, cStr)
                } else {
                    _ = git_remote_set_instance_url(remote, cStr)
                }
            }
        }

        // Preserve the original host (alias) for SSH key selection, even if we changed the connect host.
        return prepareSSHCallbacksPayload(originalHost: parts.host)
    }

    /// List all remotes
    func listRemotes() throws -> [Libgit2RemoteInfo] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var strarray = git_strarray()
        defer { git_strarray_free(&strarray) }

        let listError = git_remote_list(&strarray, ptr)
        guard listError == 0 else {
            throw Libgit2Error.from(listError, context: "remote list")
        }

        var result: [Libgit2RemoteInfo] = []

        for i in 0..<strarray.count {
            guard let namePtr = strarray.strings[i] else { continue }
            let name = String(cString: namePtr)

            var remote: OpaquePointer?
            guard git_remote_lookup(&remote, ptr, name) == 0, let r = remote else {
                continue
            }
            defer { git_remote_free(r) }

            let url = git_remote_url(r).map { String(cString: $0) }
            let pushUrl = git_remote_pushurl(r).map { String(cString: $0) }

            result.append(Libgit2RemoteInfo(
                name: name,
                url: url,
                pushUrl: pushUrl ?? url
            ))
        }

        return result
    }

    /// Get default remote (origin or first available)
    func defaultRemote() throws -> Libgit2RemoteInfo? {
        let remotes = try listRemotes()
        return remotes.first { $0.name == "origin" } ?? remotes.first
    }

    /// Fetch from remote
    func fetch(remoteName: String = "origin", prune: Bool = false) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var remote: OpaquePointer?
        let lookupError = git_remote_lookup(&remote, ptr, remoteName)
        guard lookupError == 0, let r = remote else {
            throw Libgit2Error.from(lookupError, context: "remote lookup")
        }
        defer { git_remote_free(r) }

        var opts = git_fetch_options()
        git_fetch_options_init(&opts, UInt32(GIT_FETCH_OPTIONS_VERSION))

        if prune {
            opts.prune = GIT_FETCH_PRUNE
        }

        // Setup callbacks for credential handling
        opts.callbacks.credentials = sshCredentialCallback
        let payload = configureRemoteInstanceURLIfNeeded(remote: r, forPush: false)
        opts.callbacks.payload = payload.map { UnsafeMutableRawPointer($0) }

        let fetchError = git_remote_fetch(r, nil, &opts, nil)
        freeSSHCallbacksPayload(payload)
        guard fetchError == 0 else {
            if fetchError == Int32(GIT_EAUTH.rawValue) {
                throw Libgit2Error.authenticationFailed(remoteName)
            }
            throw Libgit2Error.from(fetchError, context: "remote fetch")
        }
    }

    /// Push to remote
    func push(remoteName: String = "origin", refspecs: [String]? = nil, force: Bool = false, setUpstream: Bool = false) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var remote: OpaquePointer?
        let lookupError = git_remote_lookup(&remote, ptr, remoteName)
        guard lookupError == 0, let r = remote else {
            throw Libgit2Error.from(lookupError, context: "remote lookup")
        }
        defer { git_remote_free(r) }

        var opts = git_push_options()
        git_push_options_init(&opts, UInt32(GIT_PUSH_OPTIONS_VERSION))

        // Setup callbacks for credential handling
        opts.callbacks.credentials = sshCredentialCallback
        let payload = configureRemoteInstanceURLIfNeeded(remote: r, forPush: true)
        opts.callbacks.payload = payload.map { UnsafeMutableRawPointer($0) }

        // Build refspecs
        var refs: [String]
        if let specified = refspecs {
            refs = specified
        } else {
            // Push current branch
            if let branch = try currentBranchName() {
                let refspec = force ? "+refs/heads/\(branch):refs/heads/\(branch)" : "refs/heads/\(branch)"
                refs = [refspec]
            } else {
                throw Libgit2Error.referenceNotFound("HEAD")
            }
        }

        // Convert to C strings
        var strarray = git_strarray()
        var cStrings = refs.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }

        cStrings.withUnsafeMutableBufferPointer { buffer in
            strarray.strings = buffer.baseAddress
            strarray.count = refs.count
        }

        let pushError = git_remote_push(r, &strarray, &opts)
        freeSSHCallbacksPayload(payload)
        guard pushError == 0 else {
            if pushError == Int32(GIT_EAUTH.rawValue) {
                throw Libgit2Error.authenticationFailed(remoteName)
            }
            throw Libgit2Error.from(pushError, context: "remote push")
        }

        // Set upstream if requested
        if setUpstream, let branch = try currentBranchName() {
            try self.setUpstream(branch: branch, upstream: "\(remoteName)/\(branch)")
        }
    }

    /// Pull from remote (fetch + merge)
    func pull(remoteName: String = "origin") throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        // First fetch
        try fetch(remoteName: remoteName)

        // Get current branch
        guard let branchName = try currentBranchName() else {
            throw Libgit2Error.referenceNotFound("HEAD")
        }

        // Get remote tracking branch
        let trackingRef = "refs/remotes/\(remoteName)/\(branchName)"
        var remoteRef: OpaquePointer?
        let lookupError = git_reference_lookup(&remoteRef, ptr, trackingRef)
        guard lookupError == 0, let rRef = remoteRef else {
            // No tracking branch - nothing to merge
            return
        }
        defer { git_reference_free(rRef) }

        // Get commit to merge
        var annotatedCommit: OpaquePointer?
        let annotateError = git_annotated_commit_from_ref(&annotatedCommit, ptr, rRef)
        guard annotateError == 0, let ac = annotatedCommit else {
            throw Libgit2Error.from(annotateError, context: "annotated commit")
        }
        defer { git_annotated_commit_free(ac) }

        // Merge analysis
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
            // Already up to date
            return
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue != 0 {
            // Fast-forward merge
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

            // Checkout
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

            // Update HEAD
            var newRef: OpaquePointer?
            let refError = git_reference_set_target(&newRef, try head(), &targetOid, "pull: fast-forward")
            defer { if let r = newRef { git_reference_free(r) } }
            guard refError == 0 else {
                throw Libgit2Error.from(refError, context: "update HEAD")
            }
        } else if analysis.rawValue & GIT_MERGE_ANALYSIS_NORMAL.rawValue != 0 {
            // Normal merge
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

            // Check for conflicts in index
            let index = try getIndex()
            defer { git_index_free(index) }

            if git_index_has_conflicts(index) != 0 {
                throw Libgit2Error.mergeConflict("Merge conflicts detected. Please resolve manually.")
            }

            // Create merge commit if no conflicts
            try createMergeCommit(remoteBranch: "\(remoteName)/\(branchName)")
        }
    }

    /// Create a merge commit after successful merge
    private func createMergeCommit(remoteBranch: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        let index = try getIndex()
        defer { git_index_free(index) }

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

        // Get parents (HEAD and merge head)
        let headRef = try head()
        defer { git_reference_free(headRef) }

        var headCommit: OpaquePointer?
        let peelError = git_reference_peel(&headCommit, headRef, GIT_OBJECT_COMMIT)
        guard peelError == 0, let hc = headCommit else {
            throw Libgit2Error.from(peelError, context: "peel HEAD")
        }
        defer { git_commit_free(hc) }

        // Get merge head
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

        // Get signature
        let sig = try defaultSignature()
        defer { git_signature_free(sig) }

        // Create commit
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

        // Cleanup merge state
        git_repository_state_cleanup(ptr)
    }

    /// Add a remote
    func addRemote(name: String, url: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var remote: OpaquePointer?
        let createError = git_remote_create(&remote, ptr, name, url)
        defer { if let r = remote { git_remote_free(r) } }

        guard createError == 0 else {
            throw Libgit2Error.from(createError, context: "remote create")
        }
    }

    /// Remove a remote
    func removeRemote(name: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        let deleteError = git_remote_delete(ptr, name)
        guard deleteError == 0 else {
            throw Libgit2Error.from(deleteError, context: "remote delete")
        }
    }

    /// Get repository name from remote URL
    func repositoryName() throws -> String {
        if let remote = try defaultRemote(), let url = remote.url {
            // Extract name from URL
            let components = url.components(separatedBy: "/")
            if let last = components.last {
                return last.replacingOccurrences(of: ".git", with: "")
            }
        }

        // Fallback to directory name
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
