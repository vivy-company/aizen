import Foundation
import Clibgit2

/// File status flags
nonisolated struct Libgit2FileStatus: OptionSet, Sendable {
    let rawValue: UInt32

    static let indexNew = Libgit2FileStatus(rawValue: GIT_STATUS_INDEX_NEW.rawValue)
    static let indexModified = Libgit2FileStatus(rawValue: GIT_STATUS_INDEX_MODIFIED.rawValue)
    static let indexDeleted = Libgit2FileStatus(rawValue: GIT_STATUS_INDEX_DELETED.rawValue)
    static let indexRenamed = Libgit2FileStatus(rawValue: GIT_STATUS_INDEX_RENAMED.rawValue)
    static let indexTypeChange = Libgit2FileStatus(rawValue: GIT_STATUS_INDEX_TYPECHANGE.rawValue)

    static let wtNew = Libgit2FileStatus(rawValue: GIT_STATUS_WT_NEW.rawValue)
    static let wtModified = Libgit2FileStatus(rawValue: GIT_STATUS_WT_MODIFIED.rawValue)
    static let wtDeleted = Libgit2FileStatus(rawValue: GIT_STATUS_WT_DELETED.rawValue)
    static let wtRenamed = Libgit2FileStatus(rawValue: GIT_STATUS_WT_RENAMED.rawValue)
    static let wtTypeChange = Libgit2FileStatus(rawValue: GIT_STATUS_WT_TYPECHANGE.rawValue)
    static let wtUnreadable = Libgit2FileStatus(rawValue: GIT_STATUS_WT_UNREADABLE.rawValue)

    static let ignored = Libgit2FileStatus(rawValue: GIT_STATUS_IGNORED.rawValue)
    static let conflicted = Libgit2FileStatus(rawValue: GIT_STATUS_CONFLICTED.rawValue)

    /// File is staged (in index)
    var isStaged: Bool {
        !intersection([.indexNew, .indexModified, .indexDeleted, .indexRenamed, .indexTypeChange]).isEmpty
    }

    /// File has unstaged changes
    var isModified: Bool {
        !intersection([.wtModified, .wtDeleted, .wtTypeChange]).isEmpty
    }

    /// File is untracked
    var isUntracked: Bool {
        contains(.wtNew)
    }

    /// File has conflicts
    var isConflicted: Bool {
        contains(.conflicted)
    }
}

/// Status entry for a single file
nonisolated struct Libgit2StatusEntry: Sendable {
    let path: String
    let oldPath: String?  // For renames
    let status: Libgit2FileStatus

    /// Simplified status category
    var category: StatusCategory {
        if status.isConflicted { return .conflicted }
        if status.isStaged && !status.isModified && !status.isUntracked { return .staged }
        if status.isModified { return .modified }
        if status.isUntracked { return .untracked }
        if status.isStaged { return .staged }
        return .clean
    }

    enum StatusCategory: Sendable {
        case staged
        case modified
        case untracked
        case conflicted
        case clean
    }
}

/// Repository status summary
nonisolated struct Libgit2StatusSummary: Sendable {
    let entries: [Libgit2StatusEntry]
    let staged: [Libgit2StatusEntry]
    let modified: [Libgit2StatusEntry]
    let untracked: [Libgit2StatusEntry]
    let conflicted: [Libgit2StatusEntry]

    var hasChanges: Bool {
        !staged.isEmpty || !modified.isEmpty || !untracked.isEmpty || !conflicted.isEmpty
    }

    var hasStagedChanges: Bool {
        !staged.isEmpty
    }

    var hasUnstagedChanges: Bool {
        !modified.isEmpty || !untracked.isEmpty
    }

    var hasConflicts: Bool {
        !conflicted.isEmpty
    }
}

/// Status operations extension for Libgit2Repository
nonisolated extension Libgit2Repository {

    /// Get repository status
    func status(includeUntracked: Bool = true, includeIgnored: Bool = false) throws -> Libgit2StatusSummary {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var opts = git_status_options()
        git_status_options_init(&opts, UInt32(GIT_STATUS_OPTIONS_VERSION))

        opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        opts.flags = UInt32(GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX.rawValue) |
                     UInt32(GIT_STATUS_OPT_SORT_CASE_SENSITIVELY.rawValue)

        if includeUntracked {
            opts.flags |= UInt32(GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue)
        }
        if includeIgnored {
            opts.flags |= UInt32(GIT_STATUS_OPT_INCLUDE_IGNORED.rawValue)
        }

        var statusList: OpaquePointer?
        let listError = git_status_list_new(&statusList, ptr, &opts)
        guard listError == 0, let list = statusList else {
            throw Libgit2Error.from(listError, context: "status list")
        }
        defer { git_status_list_free(list) }

        var entries: [Libgit2StatusEntry] = []
        let count = git_status_list_entrycount(list)

        for i in 0..<count {
            guard let entry = git_status_byindex(list, i) else { continue }

            let status = Libgit2FileStatus(rawValue: entry.pointee.status.rawValue)

            // Get path from head_to_index or index_to_workdir
            var path: String = ""
            var oldPath: String? = nil

            if let headToIndex = entry.pointee.head_to_index {
                if let newFile = headToIndex.pointee.new_file.path {
                    path = String(cString: newFile)
                }
                if let oldFile = headToIndex.pointee.old_file.path {
                    let old = String(cString: oldFile)
                    if old != path {
                        oldPath = old
                    }
                }
            }

            if path.isEmpty, let indexToWorkdir = entry.pointee.index_to_workdir {
                if let newFile = indexToWorkdir.pointee.new_file.path {
                    path = String(cString: newFile)
                }
                if let oldFile = indexToWorkdir.pointee.old_file.path {
                    let old = String(cString: oldFile)
                    if old != path {
                        oldPath = old
                    }
                }
            }

            guard !path.isEmpty else { continue }

            entries.append(Libgit2StatusEntry(
                path: path,
                oldPath: oldPath,
                status: status
            ))
        }

        // Categorize entries
        let staged = entries.filter { $0.category == .staged }
        let modified = entries.filter { $0.category == .modified }
        let untracked = entries.filter { $0.category == .untracked }
        let conflicted = entries.filter { $0.category == .conflicted }

        return Libgit2StatusSummary(
            entries: entries,
            staged: staged,
            modified: modified,
            untracked: untracked,
            conflicted: conflicted
        )
    }

    /// Check if working directory is clean
    func isClean() throws -> Bool {
        let status = try status(includeUntracked: true, includeIgnored: false)
        return !status.hasChanges
    }

    /// Stage a file
    func stageFile(_ filePath: String) throws {
        guard pointer != nil else {
            throw Libgit2Error.notARepository(path)
        }

        let index = try getIndex()
        defer { git_index_free(index) }

        let addError = git_index_add_bypath(index, filePath)
        guard addError == 0 else {
            throw Libgit2Error.from(addError, context: "index add")
        }

        let writeError = git_index_write(index)
        guard writeError == 0 else {
            throw Libgit2Error.from(writeError, context: "index write")
        }
    }

    /// Stage all files
    func stageAll() throws {
        guard pointer != nil else {
            throw Libgit2Error.notARepository(path)
        }

        let index = try getIndex()
        defer { git_index_free(index) }

        var pathspec = git_strarray()
        var patterns: [UnsafeMutablePointer<CChar>?] = [strdup("*")]
        defer { patterns.forEach { free($0) } }

        let addError: Int32 = patterns.withUnsafeMutableBufferPointer { buffer in
            pathspec.strings = buffer.baseAddress
            pathspec.count = 1
            return git_index_add_all(index, &pathspec, 0, nil, nil)
        }
        guard addError == 0 else {
            throw Libgit2Error.from(addError, context: "index add all")
        }

        let writeError = git_index_write(index)
        guard writeError == 0 else {
            throw Libgit2Error.from(writeError, context: "index write")
        }
    }

    /// Unstage a file
    func unstageFile(_ filePath: String) throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        // Get HEAD commit
        var head: OpaquePointer?
        let headError = git_repository_head(&head, ptr)

        if headError == 0, let h = head {
            defer { git_reference_free(h) }

            var commit: OpaquePointer?
            let peelError = git_reference_peel(&commit, h, GIT_OBJECT_COMMIT)
            guard peelError == 0, let c = commit else {
                throw Libgit2Error.from(peelError, context: "peel HEAD")
            }
            defer { git_object_free(c) }

            // Use git_reset_default - this resets the index entry to match HEAD
            // For files in HEAD: resets to HEAD version
            // For new files (not in HEAD): removes from index entirely
            var pathspec = git_strarray()
            var patterns: [UnsafeMutablePointer<CChar>?] = [strdup(filePath)]
            defer { patterns.forEach { free($0) } }

            let resetError: Int32 = patterns.withUnsafeMutableBufferPointer { buffer in
                pathspec.strings = buffer.baseAddress
                pathspec.count = 1
                return git_reset_default(ptr, c, &pathspec)
            }
            guard resetError == 0 else {
                throw Libgit2Error.from(resetError, context: "unstage '\(filePath)'")
            }
        } else {
            // No HEAD - remove from index entirely
            let index = try getIndex()
            defer { git_index_free(index) }

            let removeError = git_index_remove_bypath(index, filePath)
            guard removeError == 0 else {
                throw Libgit2Error.from(removeError, context: "index remove (no HEAD) '\(filePath)'")
            }

            let writeError = git_index_write(index)
            guard writeError == 0 else {
                throw Libgit2Error.from(writeError, context: "index write (no HEAD) '\(filePath)'")
            }
        }
    }

    /// Unstage all files
    func unstageAll() throws {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        // Get current status to find staged files
        let currentStatus = try status()
        let stagedPaths = currentStatus.staged.map { $0.path }

        guard !stagedPaths.isEmpty else {
            return // Nothing to unstage
        }

        // Unstage each file individually
        for path in stagedPaths {
            try unstageFile(path)
        }
    }

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
