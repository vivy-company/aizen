import Foundation
import Clibgit2

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

        return Libgit2StatusSummary(
            entries: entries,
            staged: entries.filter { $0.category == .staged },
            modified: entries.filter { $0.category == .modified },
            untracked: entries.filter { $0.category == .untracked },
            conflicted: entries.filter { $0.category == .conflicted }
        )
    }

    /// Check if working directory is clean
    func isClean() throws -> Bool {
        let status = try status(includeUntracked: true, includeIgnored: false)
        return !status.hasChanges
    }
}
