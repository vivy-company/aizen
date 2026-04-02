//
//  GitOperationRunner.swift
//  aizen
//
//  Actor-backed Git mutation execution for a single worktree path.
//

import Foundation

actor GitOperationRunner {
    private let stagingService = GitStagingService()
    private let branchService = GitBranchService()
    private let remoteService = GitRemoteService()
    private let statusService = GitStatusService()

    func stageFile(at path: String, file: String) async throws {
        try await stagingService.stageFile(at: path, file: file)
    }

    func unstageFile(at path: String, file: String) async throws {
        try await stagingService.unstageFile(at: path, file: file)
    }

    func stageAll(at path: String) async throws {
        try await stagingService.stageAll(at: path)
    }

    func unstageAll(at path: String) async throws {
        try await stagingService.unstageAll(at: path)
    }

    func discardAll(at path: String) async throws {
        try await stagingService.discardAll(at: path)
    }

    func cleanUntracked(at path: String) async throws {
        try await stagingService.cleanUntracked(at: path)
    }

    func commit(at path: String, message: String) async throws {
        try await stagingService.commit(at: path, message: message)
    }

    func amendCommit(at path: String, message: String) async throws {
        try await stagingService.amendCommit(at: path, message: message)
    }

    func commitWithSignoff(at path: String, message: String) async throws {
        try await stagingService.commitWithSignoff(at: path, message: message)
    }

    func checkoutBranch(at path: String, branch: String) async throws {
        try await branchService.checkoutBranch(at: path, branch: branch)
    }

    func createBranch(at path: String, name: String, from: String?) async throws {
        try await branchService.createBranch(at: path, name: name, from: from)
    }

    func fetch(at path: String) async throws {
        try await remoteService.fetch(at: path)
    }

    func pull(at path: String) async throws {
        try await remoteService.pull(at: path)
    }

    func push(at path: String, setUpstream: Bool) async throws {
        try await remoteService.push(at: path, setUpstream: setUpstream)
    }

    func fetchThenPush(at path: String, setUpstream: Bool) async throws -> Bool {
        try await remoteService.fetch(at: path)

        let behindCount: Int
        do {
            let branchStatus = try await statusService.getBranchStatus(at: path)
            behindCount = branchStatus.behind
        } catch {
            behindCount = 0
        }

        guard behindCount == 0 else { return false }

        try await remoteService.push(at: path, setUpstream: setUpstream)
        return true
    }
}
