//
//  GitDomainService.swift
//  aizen
//
//  Base protocol for Git domain services using libgit2
//

import Foundation

/// Utility functions for Git operations
enum GitUtils {
    /// Check if a path is a git repository
    static func isGitRepository(at path: String) -> Bool {
        Libgit2Repository.isRepository(path)
    }

    /// Get main repository path (handles worktrees)
    static func getMainRepositoryPath(at path: String) -> String {
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
    }

    /// Discover repository root from a path
    static func discoverRepository(from path: String) -> String? {
        try? Libgit2Repository.discover(from: path)
    }
}
