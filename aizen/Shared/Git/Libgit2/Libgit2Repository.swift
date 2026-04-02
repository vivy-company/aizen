import Foundation
import Clibgit2

/// Swift wrapper for git_repository
/// Manages repository lifecycle and provides access to git operations
nonisolated final class Libgit2Repository {
    /// The underlying libgit2 repository pointer
    private(set) var pointer: OpaquePointer?

    /// Path to the repository
    let path: String

    /// Whether this is a bare repository
    var isBare: Bool {
        guard let ptr = pointer else { return false }
        return git_repository_is_bare(ptr) != 0
    }

    /// Whether this is an empty repository (no commits)
    var isEmpty: Bool {
        guard let ptr = pointer else { return true }
        return git_repository_is_empty(ptr) != 0
    }

    /// Whether the HEAD is detached
    var isHeadDetached: Bool {
        guard let ptr = pointer else { return false }
        return git_repository_head_detached(ptr) != 0
    }

    /// Get the workdir path
    var workdir: String? {
        guard let ptr = pointer else { return nil }
        guard let path = git_repository_workdir(ptr) else { return nil }
        return String(cString: path)
    }

    /// Get the .git directory path
    var gitdir: String? {
        guard let ptr = pointer else { return nil }
        guard let path = git_repository_path(ptr) else { return nil }
        return String(cString: path)
    }

    /// Initialize from an existing repository path
    init(path: String) throws {
        Libgit2Service.shared.ensureInitialized()

        self.path = path
        var repo: OpaquePointer?

        let error = git_repository_open(&repo, path)
        guard error == 0 else {
            if error == Int32(GIT_ENOTFOUND.rawValue) {
                throw Libgit2Error.notARepository(path)
            }
            throw Libgit2Error.from(error, context: "open repository")
        }

        self.pointer = repo
    }

    /// Initialize a new repository
    init(initAt path: String, bare: Bool = false) throws {
        Libgit2Service.shared.ensureInitialized()

        self.path = path
        var repo: OpaquePointer?

        let error = git_repository_init(&repo, path, bare ? 1 : 0)
        guard error == 0 else {
            throw Libgit2Error.from(error, context: "init repository")
        }

        self.pointer = repo
    }

    /// Clone a repository
    init(cloneFrom url: String, to localPath: String) throws {
        Libgit2Service.shared.ensureInitialized()

        self.path = localPath
        var repo: OpaquePointer?

        let error = git_clone(&repo, url, localPath, nil)
        guard error == 0 else {
            throw Libgit2Error.from(error, context: "clone repository")
        }

        self.pointer = repo
    }

    deinit {
        if let ptr = pointer {
            git_repository_free(ptr)
            pointer = nil
        }
    }

    /// Discover repository from a path (walks up directory tree)
    static func discover(from path: String) throws -> String {
        Libgit2Service.shared.ensureInitialized()

        var buf = git_buf()
        defer { git_buf_dispose(&buf) }

        let error = git_repository_discover(&buf, path, 0, nil)
        guard error == 0 else {
            if error == Int32(GIT_ENOTFOUND.rawValue) {
                throw Libgit2Error.notARepository(path)
            }
            throw Libgit2Error.from(error, context: "discover repository")
        }

        guard let ptr = buf.ptr else {
            throw Libgit2Error.notARepository(path)
        }
        return String(cString: ptr)
    }

    /// Check if a path is inside a git repository
    static func isRepository(_ path: String) -> Bool {
        do {
            _ = try discover(from: path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Index Operations

    /// Get the repository index
    func getIndex() throws -> OpaquePointer {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var index: OpaquePointer?
        let error = git_repository_index(&index, ptr)
        guard error == 0, let idx = index else {
            throw Libgit2Error.from(error, context: "get index")
        }
        return idx
    }

    // MARK: - HEAD Operations

    /// Get the current HEAD reference
    func head() throws -> OpaquePointer {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var ref: OpaquePointer?
        let error = git_repository_head(&ref, ptr)
        guard error == 0, let reference = ref else {
            throw Libgit2Error.from(error, context: "get HEAD")
        }
        return reference
    }

    /// Get the current branch name (nil if HEAD is detached)
    func currentBranchName() throws -> String? {
        guard !isHeadDetached else { return nil }

        let ref = try head()
        defer { git_reference_free(ref) }

        guard let name = git_reference_shorthand(ref) else { return nil }
        return String(cString: name)
    }

    // MARK: - Signature

    /// Get default signature from config
    func defaultSignature() throws -> UnsafeMutablePointer<git_signature> {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var sig: UnsafeMutablePointer<git_signature>?
        let error = git_signature_default(&sig, ptr)
        guard error == 0, let signature = sig else {
            throw Libgit2Error.from(error, context: "get default signature")
        }
        return signature
    }

    /// Get default signature info (name, email)
    func getSignatureInfo() throws -> (name: String, email: String) {
        let sig = try defaultSignature()
        defer { git_signature_free(sig) }
        let name = String(cString: sig.pointee.name)
        let email = String(cString: sig.pointee.email)
        return (name, email)
    }

    // MARK: - Config

    /// Get repository config
    func config() throws -> OpaquePointer {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var cfg: OpaquePointer?
        let error = git_repository_config(&cfg, ptr)
        guard error == 0, let config = cfg else {
            throw Libgit2Error.from(error, context: "get config")
        }
        return config
    }
}
