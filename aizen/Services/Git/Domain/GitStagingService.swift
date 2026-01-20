//
//  GitStagingService.swift
//  aizen
//
//  Domain service for Git staging operations using libgit2
//

import Foundation
import os.log

actor GitStagingService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "GitStagingService")

    func stageFile(at path: String, file: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.stageFile(file)
    }

    func unstageFile(at path: String, file: String) async throws {
        logger.info("unstageFile called - path: \(path), file: \(file)")
        do {
            let repo = try Libgit2Repository(path: path)
            try repo.unstageFile(file)
            logger.info("unstageFile succeeded for \(file)")
        } catch {
            logger.error("unstageFile failed for \(file): \(error.localizedDescription)")
            throw error
        }
    }

    func stageAll(at path: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.stageAll()
    }

    func unstageAll(at path: String) async throws {
        logger.info("unstageAll called - path: \(path)")
        do {
            let repo = try Libgit2Repository(path: path)
            try repo.unstageAll()
            logger.info("unstageAll succeeded")
        } catch {
            logger.error("unstageAll failed: \(error.localizedDescription)")
            throw error
        }
    }

    func commit(at path: String, message: String) async throws {
        let repo = try Libgit2Repository(path: path)
        _ = try repo.commit(message: message)
    }

    func amendCommit(at path: String, message: String) async throws {
        let repo = try Libgit2Repository(path: path)
        _ = try repo.commit(message: message, amend: true)
    }

    func commitWithSignoff(at path: String, message: String) async throws {
        let repo = try Libgit2Repository(path: path)
        let sigInfo = try repo.getSignatureInfo()
        let signoffMessage = "\(message)\n\nSigned-off-by: \(sigInfo.name) <\(sigInfo.email)>"
        _ = try repo.commit(message: signoffMessage)
    }

    func discardChanges(at path: String, file: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.discardChanges(file)
    }

    func discardAll(at path: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.discardAllChanges()
    }

    func cleanUntracked(at path: String) async throws {
        let repo = try Libgit2Repository(path: path)
        try repo.cleanUntrackedFiles()
    }
}
