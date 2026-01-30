//
//  GitLogService.swift
//  aizen
//
//  Service for fetching git commit history using libgit2
//

import Foundation

actor GitLogService {

    /// Get commit history for a repository with pagination
    func getCommitHistory(at repoPath: String, limit: Int = 30, skip: Int = 0) async throws -> [GitCommit] {
        // Actor methods run on background executor, no need for Task.detached
        let repo = try Libgit2Repository(path: repoPath)
        let commits = try repo.log(limit: limit, skip: skip)

        return commits.map { commit in
            // Get stats for this commit
            let stats = try? repo.commitStats(commit.oid)

            return GitCommit(
                id: commit.oid,
                shortHash: commit.shortOid,
                message: commit.summary,
                author: commit.author.name,
                date: commit.time,
                filesChanged: stats?.filesChanged ?? 0,
                additions: stats?.insertions ?? 0,
                deletions: stats?.deletions ?? 0
            )
        }
    }

    /// Get diff output for a specific commit
    func getCommitDiff(hash: String, at repoPath: String) async throws -> String {
        // For detailed commit diff display, use git command as libgit2 diff output
        // doesn't format nicely for display
        // Actor methods run on background executor, no need for Task.detached
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["show", "--format=", hash]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        try? pipe.fileHandleForReading.close()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
