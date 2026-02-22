//
//  GitSubmoduleService.swift
//  aizen
//
//  Domain service for Git submodule detection and initialization
//

import Foundation

nonisolated struct GitSubmoduleInfo: Sendable, Hashable, Identifiable {
    let name: String
    let path: String

    var id: String { path }
}

actor GitSubmoduleService {
    func listSubmodules(at repoPath: String) async throws -> [GitSubmoduleInfo] {
        let gitmodulesPath = (repoPath as NSString).appendingPathComponent(".gitmodules")
        guard FileManager.default.fileExists(atPath: gitmodulesPath) else {
            return []
        }

        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: ["config", "--file", ".gitmodules", "--get-regexp", #"^submodule\..*\.path$"#],
            environment: ShellEnvironment.loadUserShellEnvironment(),
            workingDirectory: repoPath
        )

        guard result.succeeded else {
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            // "no matches" is a non-error state for this command.
            if result.exitCode == 1 && stdout.isEmpty && stderr.isEmpty {
                return []
            }
            let message = stderr.isEmpty ? stdout : stderr
            throw Libgit2Error.unknownError(
                result.exitCode,
                message.isEmpty ? "Failed to list submodules" : message
            )
        }

        return parseSubmodules(from: result.stdout)
    }

    func initializeSubmodules(
        at repoPath: String,
        recursive: Bool = true,
        paths: [String] = []
    ) async throws {
        let normalizedPaths = paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        try await runSubmoduleCommand(
            at: repoPath,
            subcommand: ["sync"],
            recursive: recursive,
            paths: normalizedPaths
        )

        try await runSubmoduleCommand(
            at: repoPath,
            subcommand: ["update", "--init", "--jobs", "8"],
            recursive: recursive,
            paths: normalizedPaths
        )
    }

    func checkoutMatchingBranch(
        at repoPath: String,
        branchName: String,
        paths: [String] = []
    ) async throws {
        let selectedPaths: [String]
        if paths.isEmpty {
            selectedPaths = try await listSubmodules(at: repoPath).map(\.path)
        } else {
            selectedPaths = paths
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        for path in selectedPaths {
            let submodulePath = (repoPath as NSString).appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: submodulePath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw Libgit2Error.invalidPath("Submodule path does not exist: \(path)")
            }

            if try await hasReference("refs/heads/\(branchName)", at: submodulePath) {
                try await checkoutExistingBranch(branchName, at: submodulePath, path: path)
                continue
            }

            if try await hasReference("refs/remotes/origin/\(branchName)", at: submodulePath) {
                try await checkoutTrackingBranch(branchName, at: submodulePath, path: path)
                continue
            }

            try await createAndCheckoutBranch(branchName, at: submodulePath, path: path)
        }
    }

    private func runSubmoduleCommand(
        at repoPath: String,
        subcommand: [String],
        recursive: Bool,
        paths: [String]
    ) async throws {
        var args = ["submodule"] + subcommand
        if recursive {
            args.append("--recursive")
        }
        if !paths.isEmpty {
            args.append("--")
            args.append(contentsOf: paths)
        }

        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: args,
            environment: ShellEnvironment.loadUserShellEnvironment(),
            workingDirectory: repoPath
        )

        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw Libgit2Error.unknownError(result.exitCode, message)
        }
    }

    private func hasReference(_ ref: String, at repoPath: String) async throws -> Bool {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "--verify", "--quiet", ref],
            environment: ShellEnvironment.loadUserShellEnvironment(),
            workingDirectory: repoPath
        )
        return result.succeeded
    }

    private func checkoutExistingBranch(_ branchName: String, at repoPath: String, path: String) async throws {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: ["checkout", branchName],
            environment: ShellEnvironment.loadUserShellEnvironment(),
            workingDirectory: repoPath
        )
        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw Libgit2Error.checkoutError("Submodule \(path): \(message)")
        }
    }

    private func checkoutTrackingBranch(_ branchName: String, at repoPath: String, path: String) async throws {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: ["checkout", "-b", branchName, "--track", "origin/\(branchName)"],
            environment: ShellEnvironment.loadUserShellEnvironment(),
            workingDirectory: repoPath
        )
        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw Libgit2Error.checkoutError("Submodule \(path): \(message)")
        }
    }

    private func createAndCheckoutBranch(_ branchName: String, at repoPath: String, path: String) async throws {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: ["checkout", "-b", branchName],
            environment: ShellEnvironment.loadUserShellEnvironment(),
            workingDirectory: repoPath
        )
        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw Libgit2Error.checkoutError("Submodule \(path): \(message)")
        }
    }

    private func parseSubmodules(from output: String) -> [GitSubmoduleInfo] {
        var submodules: [GitSubmoduleInfo] = []
        var seenPaths = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let keyTerminator = line.firstIndex(where: \.isWhitespace) else { continue }

            let key = String(line[..<keyTerminator])
            let pathStart = line.index(after: keyTerminator)
            let path = String(line[pathStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            guard !seenPaths.contains(path) else { continue }

            let name: String
            if key.hasPrefix("submodule."), key.hasSuffix(".path") {
                name = String(key.dropFirst("submodule.".count).dropLast(".path".count))
            } else {
                name = path
            }

            submodules.append(GitSubmoduleInfo(name: name, path: path))
            seenPaths.insert(path)
        }

        return submodules.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }
}
