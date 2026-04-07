import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {
    /// Get commit log
    func log(limit: Int = 50, skip: Int = 0) throws -> [Libgit2CommitInfo] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var revwalk: OpaquePointer?
        let walkError = git_revwalk_new(&revwalk, ptr)
        guard walkError == 0, let walk = revwalk else {
            throw Libgit2Error.from(walkError, context: "revwalk new")
        }
        defer { git_revwalk_free(walk) }

        git_revwalk_sorting(walk, UInt32(GIT_SORT_TIME.rawValue))

        let pushError = git_revwalk_push_head(walk)
        guard pushError == 0 else {
            return []
        }

        var result: [Libgit2CommitInfo] = []
        var oid = git_oid()
        var skipped = 0

        while git_revwalk_next(&oid, walk) == 0 {
            if skipped < skip {
                skipped += 1
                continue
            }

            if result.count >= limit {
                break
            }

            var commit: OpaquePointer?
            guard git_commit_lookup(&commit, ptr, &oid) == 0, let c = commit else {
                continue
            }
            defer { git_commit_free(c) }

            result.append(parseCommit(c, oid: &oid))
        }

        return result
    }

    /// Get a specific commit by hash
    func getCommit(_ hash: String) throws -> Libgit2CommitInfo {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var oid = git_oid()
        let parseError = git_oid_fromstr(&oid, hash)
        guard parseError == 0 else {
            throw Libgit2Error.from(parseError, context: "parse oid")
        }

        var commit: OpaquePointer?
        let lookupError = git_commit_lookup(&commit, ptr, &oid)
        guard lookupError == 0, let c = commit else {
            throw Libgit2Error.from(lookupError, context: "commit lookup")
        }
        defer { git_commit_free(c) }

        return parseCommit(c, oid: &oid)
    }

    /// Get commit stats (files changed, insertions, deletions)
    func commitStats(_ hash: String) throws -> Libgit2DiffStats {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var oid = git_oid()
        let parseError = git_oid_fromstr(&oid, hash)
        guard parseError == 0 else {
            throw Libgit2Error.from(parseError, context: "parse oid")
        }

        var commit: OpaquePointer?
        let lookupError = git_commit_lookup(&commit, ptr, &oid)
        guard lookupError == 0, let c = commit else {
            throw Libgit2Error.from(lookupError, context: "commit lookup")
        }
        defer { git_commit_free(c) }

        var tree: OpaquePointer?
        let treeError = git_commit_tree(&tree, c)
        guard treeError == 0, let t = tree else {
            throw Libgit2Error.from(treeError, context: "commit tree")
        }
        defer { git_tree_free(t) }

        var parentTree: OpaquePointer? = nil
        if git_commit_parentcount(c) > 0 {
            var parent: OpaquePointer?
            if git_commit_parent(&parent, c, 0) == 0, let p = parent {
                defer { git_commit_free(p) }
                var pt: OpaquePointer?
                if git_commit_tree(&pt, p) == 0 {
                    parentTree = pt
                }
            }
        }
        defer { if let pt = parentTree { git_tree_free(pt) } }

        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))

        let diffError = git_diff_tree_to_tree(&diff, ptr, parentTree, t, &opts)
        guard diffError == 0, let d = diff else {
            throw Libgit2Error.from(diffError, context: "diff tree to tree")
        }
        defer { git_diff_free(d) }

        var stats: OpaquePointer?
        let statsError = git_diff_get_stats(&stats, d)
        guard statsError == 0, let s = stats else {
            throw Libgit2Error.from(statsError, context: "diff stats")
        }
        defer { git_diff_stats_free(s) }

        return Libgit2DiffStats(
            filesChanged: git_diff_stats_files_changed(s),
            insertions: git_diff_stats_insertions(s),
            deletions: git_diff_stats_deletions(s)
        )
    }

    func parseCommit(_ commit: OpaquePointer, oid: inout git_oid) -> Libgit2CommitInfo {
        var oidStr = [CChar](repeating: 0, count: 41)
        git_oid_tostr(&oidStr, 41, &oid)
        let fullOid = String(cString: oidStr)

        var shortOidStr = [CChar](repeating: 0, count: 8)
        git_oid_tostr(&shortOidStr, 8, &oid)
        let shortOid = String(cString: shortOidStr)

        let message = git_commit_message(commit).map { String(cString: $0) } ?? ""
        let summary = git_commit_summary(commit).map { String(cString: $0) } ?? ""

        let authorSig = git_commit_author(commit)
        let author = parseSignature(authorSig)

        let committerSig = git_commit_committer(commit)
        let committer = parseSignature(committerSig)

        let parentCount = Int(git_commit_parentcount(commit))
        let timestamp = git_commit_time(commit)
        let time = Date(timeIntervalSince1970: TimeInterval(timestamp))

        return Libgit2CommitInfo(
            oid: fullOid,
            shortOid: shortOid,
            message: message,
            summary: summary,
            author: author,
            committer: committer,
            parentCount: parentCount,
            time: time
        )
    }

    func parseSignature(_ sig: UnsafePointer<git_signature>?) -> Libgit2Signature {
        guard let s = sig else {
            return Libgit2Signature(name: "Unknown", email: "", time: Date())
        }

        let name = s.pointee.name.map { String(cString: $0) } ?? "Unknown"
        let email = s.pointee.email.map { String(cString: $0) } ?? ""
        let time = Date(timeIntervalSince1970: TimeInterval(s.pointee.when.time))

        return Libgit2Signature(name: name, email: email, time: time)
    }
}
