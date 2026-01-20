//
//  GitRemoteService.swift
//  aizen
//
//  Domain service for Git remote operations using libgit2
//

import Foundation

actor GitRemoteService {

    private func isSSHRemoteURL(_ url: String) -> Bool {
        if url.hasPrefix("ssh://") { return true }
        if url.contains("://") { return false }
        // SCP-like: [user@]host:path
        if let colon = url.firstIndex(of: ":") {
            let before = url[..<colon]
            if !before.isEmpty, !before.contains("/") {
                return true
            }
        }
        return false
    }

    func fetch(at path: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.fetch()
    }

    func pull(at path: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.pull()
    }

    func push(at path: String, setUpstream: Bool = false, force: Bool = false) async throws {
        let repo = try Libgit2Repository(path: path)

        // Build refspecs if force push
        var refspecs: [String]? = nil
        if force {
            if let branch = try repo.currentBranchName() {
                refspecs = ["+refs/heads/\(branch):refs/heads/\(branch)"]
            }
        }

        try repo.push(refspecs: refspecs, setUpstream: setUpstream)
    }

    func clone(url: String, to path: String) async throws {
        // Prefer git CLI for SSH clones to respect ~/.ssh/config host aliases and advanced ssh options.
        if isSSHRemoteURL(url) {
            let environment = ShellEnvironment.loadUserShellEnvironment()
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["clone", url, path],
                environment: environment,
                workingDirectory: nil
            )
            guard result.succeeded else {
                throw Libgit2Error.networkError(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
            return
        }

        _ = try Libgit2Repository(cloneFrom: url, to: path)
    }

    func initRepository(at path: String, initialBranch: String = "main") async throws {
        // Create directory if doesn't exist
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Initialize git repository
        _ = try Libgit2Repository(initAt: path)

        // Set initial branch name - libgit2 defaults to "master", so rename if needed
        if initialBranch != "master" {
            // Use shell command for this edge case
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["symbolic-ref", "HEAD", "refs/heads/\(initialBranch)"]
            process.currentDirectoryURL = URL(fileURLWithPath: path)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
    }

    func getRepositoryName(at path: String) async throws -> String {
        let repo = try Libgit2Repository(path: path)
        return try repo.repositoryName()
    }
}
