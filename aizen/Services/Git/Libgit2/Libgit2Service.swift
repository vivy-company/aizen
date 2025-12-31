import Foundation
import Clibgit2

/// Manages libgit2 library lifecycle
/// Thread-safe singleton that initializes libgit2 once and shuts it down on app termination
final class Libgit2Service: @unchecked Sendable {
    static let shared = Libgit2Service()

    private let lock = NSLock()
    private var isInitialized = false

    private init() {
        initialize()
    }

    deinit {
        shutdown()
    }

    /// Initialize libgit2 library (called automatically on first access)
    private func initialize() {
        lock.lock()
        defer { lock.unlock() }

        guard !isInitialized else { return }

        let result = git_libgit2_init()
        if result >= 0 {
            isInitialized = true
        }
    }

    /// Shutdown libgit2 library
    private func shutdown() {
        lock.lock()
        defer { lock.unlock() }

        guard isInitialized else { return }

        git_libgit2_shutdown()
        isInitialized = false
    }

    /// Ensure libgit2 is initialized before any operation
    func ensureInitialized() {
        if !isInitialized {
            initialize()
        }
    }

    /// Get libgit2 version information
    var version: (major: Int, minor: Int, rev: Int) {
        var major: Int32 = 0
        var minor: Int32 = 0
        var rev: Int32 = 0
        git_libgit2_version(&major, &minor, &rev)
        return (Int(major), Int(minor), Int(rev))
    }

    /// Get libgit2 features
    var features: Libgit2Features {
        let flags = git_libgit2_features()
        return Libgit2Features(rawValue: flags)
    }
}

/// libgit2 compile-time features
nonisolated struct Libgit2Features: OptionSet {
    let rawValue: Int32

    static let threads = Libgit2Features(rawValue: Int32(GIT_FEATURE_THREADS.rawValue))
    static let https = Libgit2Features(rawValue: Int32(GIT_FEATURE_HTTPS.rawValue))
    static let ssh = Libgit2Features(rawValue: Int32(GIT_FEATURE_SSH.rawValue))
    static let nsec = Libgit2Features(rawValue: Int32(GIT_FEATURE_NSEC.rawValue))
}
