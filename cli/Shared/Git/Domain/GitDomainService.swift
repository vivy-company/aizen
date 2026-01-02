//
//  GitDomainService.swift
//  aizen
//
//  Base protocol for Git domain services using libgit2
//

import Foundation

/// Utility functions for Git operations (async to avoid blocking main thread)
enum GitUtils {
    /// Check if a path is a git repository (async - runs libgit2 off main thread)
    static func isGitRepository(at path: String) async -> Bool {
        await Task.detached {
            Libgit2Repository.isRepository(path)
        }.value
    }

    /// Get main repository path (handles worktrees) - async for file I/O
    static func getMainRepositoryPath(at path: String) async -> String {
        await Task.detached {
            let gitPath = (path as NSString).appendingPathComponent(".git")

            if let gitContent = try? String(contentsOfFile: gitPath, encoding: .utf8),
               gitContent.hasPrefix("gitdir: ") {
                // Parse gitdir path and extract main repo location
                let gitdir = gitContent
                    .replacingOccurrences(of: "gitdir: ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // gitdir points to .git/worktrees/<name>, we need to go up to main repo
                let gitdirURL = URL(fileURLWithPath: gitdir)
                let mainGitPath = gitdirURL.deletingLastPathComponent().deletingLastPathComponent().path
                return mainGitPath.replacingOccurrences(of: "/.git", with: "")
            }

            // This is the main repository
            return path
        }.value
    }

    /// Discover repository root from a path (async)
    static func discoverRepository(from path: String) async -> String? {
        await Task.detached {
            try? Libgit2Repository.discover(from: path)
        }.value
    }
}
