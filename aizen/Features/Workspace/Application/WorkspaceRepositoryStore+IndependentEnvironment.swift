//
//  WorkspaceRepositoryStore+IndependentEnvironment.swift
//  aizen
//
//  Independent environment creation flow.
//

import CoreData
import Foundation

extension WorkspaceRepositoryStore {
    func addIndependentEnvironment(
        to repository: Repository,
        path: String,
        sourcePath: String,
        method: IndependentEnvironmentMethod,
        runPostCreateActions: Bool = true
    ) async throws -> Worktree {
        let source = normalizedPath(sourcePath)
        let destination = normalizedPath(path)

        guard FileManager.default.fileExists(atPath: source) else {
            throw Libgit2Error.invalidPath("Source path not found: \(source)")
        }
        guard !FileManager.default.fileExists(atPath: destination) else {
            throw Libgit2Error.unknownError(0, "Directory already exists")
        }

        let destinationParent = URL(fileURLWithPath: destination).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        switch method {
        case .clone:
            guard GitUtils.isGitRepository(at: source) else {
                throw Libgit2Error.notARepository(source)
            }
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["clone", "--local", source, destination],
                environment: ShellEnvironment.loadUserShellEnvironment()
            )
            guard result.succeeded else {
                let message = result.stderr.isEmpty ? result.stdout : result.stderr
                throw Libgit2Error.unknownError(result.exitCode, message)
            }
        case .copy:
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/rsync",
                arguments: ["-a", "--exclude", ".git", "\(source)/", "\(destination)/"]
            )
            guard result.succeeded else {
                let message = result.stderr.isEmpty ? result.stdout : result.stderr
                throw Libgit2Error.unknownError(result.exitCode, message)
            }
        }

        let environmentName = defaultEnvironmentName(for: destination)
        let branchName: String
        if GitUtils.isGitRepository(at: destination) {
            branchName = (try? await statusService.getCurrentBranch(at: destination)) ?? environmentName
        } else {
            branchName = environmentName
        }

        let environment = Worktree(context: viewContext)
        environment.id = UUID()
        environment.path = destination
        environment.branch = branchName
        environment.isPrimary = false
        environment.checkoutTypeValue = .independent
        environment.repository = repository
        environment.lastAccessed = Date()

        try viewContext.save()
        if runPostCreateActions {
            await executePostCreateActions(for: repository, newWorktreePath: destination)
        }
        return environment
    }
}
