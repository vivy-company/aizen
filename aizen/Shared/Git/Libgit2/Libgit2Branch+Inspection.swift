import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {
    /// List all branches
    func listBranches(type: Libgit2BranchType = .all, includeUpstreamInfo: Bool = false) throws -> [Libgit2BranchInfo] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var iterator: OpaquePointer?
        let iterError = git_branch_iterator_new(&iterator, ptr, type.gitType)
        guard iterError == 0, let iter = iterator else {
            throw Libgit2Error.from(iterError, context: "branch iterator")
        }
        defer { git_branch_iterator_free(iter) }

        var result: [Libgit2BranchInfo] = []
        var ref: OpaquePointer?
        var branchType: git_branch_t = GIT_BRANCH_LOCAL

        while git_branch_next(&ref, &branchType, iter) == 0 {
            guard let reference = ref else { continue }
            defer { git_reference_free(reference) }

            guard let namePtr = git_reference_shorthand(reference) else { continue }
            let name = String(cString: namePtr)

            guard let fullNamePtr = git_reference_name(reference) else { continue }
            let fullName = String(cString: fullNamePtr)

            let isRemote = branchType == GIT_BRANCH_REMOTE
            let isHead = git_branch_is_head(reference) != 0

            var upstream: String? = nil
            var aheadBehind: (ahead: Int, behind: Int)? = nil

            if includeUpstreamInfo, !isRemote {
                var upstreamRef: OpaquePointer?
                if git_branch_upstream(&upstreamRef, reference) == 0, let ur = upstreamRef {
                    defer { git_reference_free(ur) }
                    if let upstreamName = git_reference_shorthand(ur) {
                        upstream = String(cString: upstreamName)
                    }

                    var localOid = git_oid()
                    var upstreamOid = git_oid()

                    if git_reference_name_to_id(&localOid, ptr, fullName) == 0,
                       let urName = git_reference_name(ur),
                       git_reference_name_to_id(&upstreamOid, ptr, urName) == 0 {
                        var ahead: Int = 0
                        var behind: Int = 0
                        if git_graph_ahead_behind(&ahead, &behind, ptr, &localOid, &upstreamOid) == 0 {
                            aheadBehind = (ahead, behind)
                        }
                    }
                }
            }

            result.append(Libgit2BranchInfo(
                name: name,
                fullName: fullName,
                isRemote: isRemote,
                isHead: isHead,
                upstream: upstream,
                aheadBehind: aheadBehind
            ))
        }

        return result
    }

    func shortOid(forReferenceFullName fullName: String) throws -> String {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var oid = git_oid()
        let err = git_reference_name_to_id(&oid, ptr, fullName)
        guard err == 0 else {
            throw Libgit2Error.from(err, context: "reference name to id")
        }

        var buffer = [CChar](repeating: 0, count: Int(GIT_OID_HEXSZ) + 1)
        _ = buffer.withUnsafeMutableBufferPointer { buf in
            git_oid_tostr(buf.baseAddress, buf.count, &oid)
        }
        let hex = String(cString: buffer)
        return String(hex.prefix(7))
    }

    /// Calculate ahead/behind for the current HEAD's upstream (fast path).
    func headAheadBehind() throws -> (ahead: Int, behind: Int) {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        guard git_repository_head_detached(ptr) == 0 else {
            return (0, 0)
        }

        var headRef: OpaquePointer?
        let headError = git_repository_head(&headRef, ptr)
        guard headError == 0, let head = headRef else {
            return (0, 0)
        }
        defer { git_reference_free(head) }

        var upstreamRef: OpaquePointer?
        let upstreamError = git_branch_upstream(&upstreamRef, head)
        guard upstreamError == 0, let upstream = upstreamRef else {
            return (0, 0)
        }
        defer { git_reference_free(upstream) }

        guard let headFullName = git_reference_name(head),
              let upstreamFullName = git_reference_name(upstream) else {
            return (0, 0)
        }

        var localOid = git_oid()
        var upstreamOid = git_oid()

        guard git_reference_name_to_id(&localOid, ptr, headFullName) == 0,
              git_reference_name_to_id(&upstreamOid, ptr, upstreamFullName) == 0 else {
            return (0, 0)
        }

        var ahead: Int = 0
        var behind: Int = 0
        guard git_graph_ahead_behind(&ahead, &behind, ptr, &localOid, &upstreamOid) == 0 else {
            return (0, 0)
        }

        return (ahead, behind)
    }
}
