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
