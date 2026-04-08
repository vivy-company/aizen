import Foundation
import Clibgit2

/// Working tree cleanup operations for Libgit2Repository
nonisolated extension Libgit2Repository {

    /// Discard changes in a file (restore from index)
    func discardChanges(_ filePath: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var opts = git_checkout_options()
        git_checkout_options_init(&opts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        opts.checkout_strategy = UInt32(GIT_CHECKOUT_FORCE.rawValue)

        var pathspec = git_strarray()
        var patterns: [UnsafeMutablePointer<CChar>?] = [strdup(filePath)]
        defer { patterns.forEach { free($0) } }

        let checkoutError: Int32 = patterns.withUnsafeMutableBufferPointer { buffer in
            pathspec.strings = buffer.baseAddress
            pathspec.count = 1
            opts.paths = pathspec
            return git_checkout_index(ptr, nil, &opts)
        }
        guard checkoutError == 0 else {
            throw Libgit2Error.from(checkoutError, context: "checkout index")
        }
    }

    /// Discard all changes (reset working tree to HEAD)
    func discardAllChanges() throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        // Get HEAD commit
        var head: OpaquePointer?
        let headError = git_repository_head(&head, ptr)
        guard headError == 0, let h = head else {
            throw Libgit2Error.from(headError, context: "get HEAD")
        }
        defer { git_reference_free(h) }

        var commit: OpaquePointer?
        let peelError = git_reference_peel(&commit, h, GIT_OBJECT_COMMIT)
        guard peelError == 0, let c = commit else {
            throw Libgit2Error.from(peelError, context: "peel HEAD")
        }
        defer { git_object_free(c) }

        // Hard reset to HEAD - this resets both index and working tree
        let resetError = git_reset(ptr, c, GIT_RESET_HARD, nil)
        guard resetError == 0 else {
            throw Libgit2Error.from(resetError, context: "reset hard")
        }
    }

    /// Remove untracked files from working directory
    func cleanUntrackedFiles() throws {
        guard pointer != nil else {
            throw Libgit2Error.notARepository(path)
        }

        // Get status to find untracked files
        let currentStatus = try status()
        let untrackedPaths = currentStatus.untracked.map { $0.path }

        guard !untrackedPaths.isEmpty else {
            return // Nothing to clean
        }

        let fileManager = FileManager.default
        for relativePath in untrackedPaths {
            let fullPath = (path as NSString).appendingPathComponent(relativePath)
            try? fileManager.removeItem(atPath: fullPath)
        }
    }
}
