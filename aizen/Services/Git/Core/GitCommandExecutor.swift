//
//  GitCommandExecutor.swift
//  aizen
//
//  Low-level Git command execution
//  Shared by all domain services
//

import Foundation

enum GitError: LocalizedError {
    case commandFailed(message: String)
    case invalidPath
    case notAGitRepository
    case worktreeNotFound

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return String(localized: "error.git.commandFailed \(message)")
        case .invalidPath:
            return String(localized: "error.git.invalidPath")
        case .notAGitRepository:
            return String(localized: "error.git.notRepository")
        case .worktreeNotFound:
            return String(localized: "error.git.worktreeNotFound")
        }
    }
}

actor GitCommandExecutor {

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private func getShellEnvironment() -> [String: String] {
        return ShellEnvironment.loadUserShellEnvironment()
    }

    /// Execute a git command fully asynchronously without blocking
    func executeGit(arguments: [String], at workingDirectory: String?) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            var environment = self.getShellEnvironment()
            environment["GIT_PAGER"] = "cat"
            process.environment = environment

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            // Set up async termination handler
            process.terminationHandler = { process in
                // Read output asynchronously (on Process's internal queue)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: data, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let errorMessage = stderr.isEmpty ? String(localized: "error.git.unknownError") : stderr
                    continuation.resume(throwing: GitError.commandFailed(message: errorMessage))
                } else {
                    continuation.resume(returning: stdout)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Check if a path is a git repository
    func isGitRepository(at path: String) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: gitPath, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            return true
        }

        // Check if it's a worktree (has .git file pointing to main repo)
        if fileManager.fileExists(atPath: gitPath) {
            return true
        }

        return false
    }

    /// Get main repository path (handles worktrees)
    func getMainRepositoryPath(at path: String) -> String {
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
}
