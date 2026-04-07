import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {

    /// List all worktrees in the repository
    func listWorktrees() throws -> [Libgit2WorktreeInfo] {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var strarray = git_strarray()
        defer { git_strarray_free(&strarray) }

        let error = git_worktree_list(&strarray, ptr)
        guard error == 0 else {
            throw Libgit2Error.from(error, context: "worktree list")
        }

        var result: [Libgit2WorktreeInfo] = []

        if let workdir = self.workdir {
            let mainBranch = try? currentBranchName()
            var normalizedPath = workdir
            while normalizedPath.hasSuffix("/") {
                normalizedPath = String(normalizedPath.dropLast())
            }
            result.append(Libgit2WorktreeInfo(
                name: "",
                path: normalizedPath,
                isLocked: false,
                isValid: true,
                branch: mainBranch
            ))
        }

        for i in 0..<strarray.count {
            guard let namePtr = strarray.strings[i] else { continue }
            let name = String(cString: namePtr)

            var wt: OpaquePointer?
            guard git_worktree_lookup(&wt, ptr, name) == 0, let worktree = wt else {
                continue
            }
            defer { git_worktree_free(worktree) }

            guard let pathPtr = git_worktree_path(worktree) else {
                continue
            }

            var wtPath = String(cString: pathPtr)
            while wtPath.hasSuffix("/") {
                wtPath = String(wtPath.dropLast())
            }

            let isValid = git_worktree_validate(worktree) == 0
            let isLocked = git_worktree_is_locked(nil, worktree) > 0
            let branch = isValid ? (try? getWorktreeBranch(name: name)) : nil

            result.append(Libgit2WorktreeInfo(
                name: name,
                path: wtPath,
                isLocked: isLocked,
                isValid: isValid,
                branch: branch
            ))
        }

        return result
    }

    /// Validate a worktree
    func validateWorktree(name: String) throws -> Bool {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var wt: OpaquePointer?
        let lookupError = git_worktree_lookup(&wt, ptr, name)
        guard lookupError == 0, let worktree = wt else {
            throw Libgit2Error.worktreeNotFound(name)
        }
        defer { git_worktree_free(worktree) }

        return git_worktree_validate(worktree) == 0
    }

    func getWorktreeBranch(name: String) throws -> String? {
        guard let ptr = pointer else {
            throw Libgit2Error.notARepository(path)
        }

        var wt: OpaquePointer?
        let lookupError = git_worktree_lookup(&wt, ptr, name)
        guard lookupError == 0, let worktree = wt else {
            throw Libgit2Error.from(lookupError, context: "worktree lookup")
        }
        defer { git_worktree_free(worktree) }

        guard let wtPath = git_worktree_path(worktree) else {
            return nil
        }

        var wtRepo: OpaquePointer?
        let openError = git_repository_open(&wtRepo, String(cString: wtPath))
        guard openError == 0, let repo = wtRepo else {
            return nil
        }
        defer { git_repository_free(repo) }

        var head: OpaquePointer?
        let headError = git_repository_head(&head, repo)
        guard headError == 0, let ref = head else {
            return nil
        }
        defer { git_reference_free(ref) }

        guard let shorthand = git_reference_shorthand(ref) else {
            return nil
        }
        return String(cString: shorthand)
    }
}
