//
//  GitService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
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

struct WorktreeInfo {
    let path: String
    let branch: String
    let commit: String
    let isPrimary: Bool
}

struct BranchInfo: Hashable, Identifiable {
    let id = UUID()
    let name: String
    let commit: String
    let isRemote: Bool
}

struct GitStatus {
    var modifiedFiles: [String]
    var stagedFiles: [String]
    var untrackedFiles: [String]
}

actor GitService {

    // MARK: - Validation

    func isGitRepository(at path: String) async throws -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            return true
        }

        // Check if it's a worktree (has .git file pointing to main repo)
        if FileManager.default.fileExists(atPath: gitPath) {
            return true
        }

        return false
    }

    // MARK: - Repository Info

    func getRepositoryName(at path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent
    }

    func getMainRepositoryPath(at path: String) async throws -> String {
        // If this is a worktree, get the main repo path from .git file
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

    // MARK: - Worktree Operations

    func listWorktrees(at repoPath: String) async throws -> [WorktreeInfo] {
        let output = try await executeGit(arguments: ["worktree", "list", "--porcelain"], at: repoPath)
        return parseWorktreeList(output, repositoryPath: repoPath)
    }

    func addWorktree(at repoPath: String, path: String, branch: String, createBranch: Bool = false, baseBranch: String? = nil) async throws {
        var arguments = ["worktree", "add"]

        if createBranch {
            arguments.append("-b")
            arguments.append(branch)
        }

        arguments.append(path)

        // If creating a new branch, specify the base branch
        if createBranch, let baseBranch = baseBranch {
            arguments.append(baseBranch)
        } else if !createBranch {
            // If not creating, just checkout the existing branch
            arguments.append(branch)
        }

        _ = try await executeGit(arguments: arguments, at: repoPath)
    }

    func hasUnsavedChanges(at worktreePath: String) async throws -> Bool {
        let output = try await executeGit(arguments: ["status", "--porcelain"], at: worktreePath)
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func removeWorktree(at worktreePath: String, repoPath: String, force: Bool = false) async throws {
        var arguments = ["worktree", "remove"]

        if force {
            arguments.append("--force")
        }

        arguments.append(worktreePath)

        _ = try await executeGit(arguments: arguments, at: repoPath)
    }

    // MARK: - Branch Operations

    func listBranches(at repoPath: String, includeRemote: Bool = true) async throws -> [BranchInfo] {
        var arguments = ["branch", "-v", "--no-color"]
        if includeRemote {
            arguments.append("-a")
        }

        let output = try await executeGit(arguments: arguments, at: repoPath)
        return parseBranchList(output)
    }

    func getCurrentBranch(at path: String) async throws -> String {
        let output = try await executeGit(arguments: ["branch", "--show-current"], at: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func getBranchStatus(at path: String) async throws -> (ahead: Int, behind: Int) {
        let output = try await executeGit(arguments: ["status", "-sb", "--porcelain"], at: path)

        // Parse output like "## main...origin/main [ahead 2, behind 1]"
        let lines = output.split(separator: "\n")
        guard let statusLine = lines.first, statusLine.hasPrefix("##") else {
            return (0, 0)
        }

        var ahead = 0
        var behind = 0

        if let aheadRange = statusLine.range(of: "ahead (\\d+)", options: .regularExpression) {
            let aheadStr = statusLine[aheadRange].split(separator: " ").last.map(String.init) ?? "0"
            ahead = Int(aheadStr) ?? 0
        }

        if let behindRange = statusLine.range(of: "behind (\\d+)", options: .regularExpression) {
            let behindStr = statusLine[behindRange].split(separator: " ").last.map(String.init) ?? "0"
            behind = Int(behindStr) ?? 0
        }

        return (ahead, behind)
    }

    // MARK: - Clone

    func clone(url: String, to path: String) async throws {
        _ = try await executeGit(arguments: ["clone", url, path], at: nil)
    }

    // MARK: - Private Helpers

    private func executeGit(arguments: [String], at workingDirectory: String?) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: data, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errorMessage = stderr.isEmpty ? String(localized: "error.git.unknownError") : stderr
            throw GitError.commandFailed(message: errorMessage)
        }

        return stdout
    }

    private func parseWorktreeList(_ output: String, repositoryPath: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentWorktree: [String: String] = [:]

        // Use components(separatedBy:) instead of split() to preserve empty strings
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                if let path = currentWorktree["worktree"],
                   let branch = currentWorktree["branch"],
                   let commit = currentWorktree["HEAD"] {

                    let cleanBranch = branch.replacingOccurrences(of: "refs/heads/", with: "")
                    let isPrimary = path == repositoryPath

                    worktrees.append(WorktreeInfo(
                        path: path,
                        branch: cleanBranch,
                        commit: commit,
                        isPrimary: isPrimary
                    ))
                }
                currentWorktree.removeAll()
                continue
            }

            let components = trimmedLine.split(separator: " ", maxSplits: 1).map(String.init)
            if components.count == 2 {
                currentWorktree[components[0]] = components[1]
            }
        }

        // Handle last worktree
        if let path = currentWorktree["worktree"],
           let branch = currentWorktree["branch"],
           let commit = currentWorktree["HEAD"] {

            let cleanBranch = branch.replacingOccurrences(of: "refs/heads/", with: "")
            let isPrimary = path == repositoryPath

            worktrees.append(WorktreeInfo(
                path: path,
                branch: cleanBranch,
                commit: commit,
                isPrimary: isPrimary
            ))
        }

        return worktrees
    }

    private func parseBranchList(_ output: String) -> [BranchInfo] {
        let lines = output.split(separator: "\n").map(String.init)
        var branches: [BranchInfo] = []

        for line in lines {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "* ", with: "")
                .replacingOccurrences(of: "+ ", with: "")
                .replacingOccurrences(of: "  ", with: " ")

            let components = cleaned.split(separator: " ", maxSplits: 2).map(String.init)
            guard components.count >= 2 else { continue }

            let name = components[0]
            let commit = components[1]
            let isRemote = name.hasPrefix("remotes/")

            branches.append(BranchInfo(
                name: name.replacingOccurrences(of: "remotes/", with: ""),
                commit: commit,
                isRemote: isRemote
            ))
        }

        return branches
    }
}
