import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {
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

        opts.callbacks.credentials = sshCredentialCallback
        let payload = configureRemoteInstanceURLIfNeeded(remote: r, forPush: true)
        opts.callbacks.payload = payload.map { UnsafeMutableRawPointer($0) }

        let refs: [String]
        if let specified = refspecs {
            refs = specified
        } else if let branch = try currentBranchName() {
            let refspec = force ? "+refs/heads/\(branch):refs/heads/\(branch)" : "refs/heads/\(branch)"
            refs = [refspec]
        } else {
            throw Libgit2Error.referenceNotFound("HEAD")
        }

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

        if setUpstream, let branch = try currentBranchName() {
            try self.setUpstream(branch: branch, upstream: "\(remoteName)/\(branch)")
        }
    }
}
