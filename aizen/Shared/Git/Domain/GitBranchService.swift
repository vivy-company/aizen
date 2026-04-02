//
//  GitBranchService.swift
//  aizen
//
//  Domain service for Git branch operations using libgit2
//

import Foundation

nonisolated struct BranchInfo: Hashable, Identifiable, Sendable {
    let id = UUID()
    let name: String
    let commit: String
    let isRemote: Bool
}

actor GitBranchService {

    func listBranches(at repoPath: String, includeRemote: Bool = true) async throws -> [BranchInfo] {
        let repo = try Libgit2Repository(path: repoPath)
        let type: Libgit2BranchType = includeRemote ? .all : .local
        let branches = try repo.listBranches(type: type, includeUpstreamInfo: false)

        // Get commits for branches
        var result: [BranchInfo] = []
        for branch in branches {
            // Skip HEAD references
            if branch.name == "HEAD" || branch.name.hasSuffix("/HEAD") {
                continue
            }

            // Get short commit hash
            let commit = (try? repo.shortOid(forReferenceFullName: branch.fullName)) ?? ""

            result.append(BranchInfo(
                name: branch.name,
                commit: commit,
                isRemote: branch.isRemote
            ))
        }

        return result
    }

    func checkoutBranch(at path: String, branch: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.checkoutBranch(name: branch)
    }

    func createBranch(at path: String, name: String, from baseBranch: String? = nil) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.createBranch(name: name, from: baseBranch)
        // Checkout the new branch
        try repo.checkoutBranch(name: name)
    }

    func deleteBranch(at path: String, name: String, force: Bool = false) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.deleteBranch(name: name, force: force)
    }

    func mergeBranch(at path: String, branch: String) async throws -> MergeResult {
        // libgit2 merge is complex - use git command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["merge", branch]
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: (try? pipe.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
        let errorOutput = String(data: (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
        try? pipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        if process.terminationStatus == 0 {
            if output.contains("Already up to date") || output.contains("Already up-to-date") {
                return MergeResult.alreadyUpToDate
            }
            return MergeResult.success
        }

        // Check for conflicts
        if errorOutput.contains("CONFLICT") || errorOutput.contains("Merge conflict") || output.contains("CONFLICT") {
            let repo = try Libgit2Repository(path: path)
            let status = try repo.status()
            let conflictedFiles = status.conflicted.map { $0.path }
            return MergeResult.conflict(files: conflictedFiles)
        }

        throw Libgit2Error.mergeConflict(errorOutput)
    }
}
