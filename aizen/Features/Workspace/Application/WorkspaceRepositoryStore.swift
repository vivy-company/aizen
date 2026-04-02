//
//  WorkspaceRepositoryStore.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import CoreData
import AppKit
import Combine
import os.log

@MainActor
class WorkspaceRepositoryStore: ObservableObject {
    enum IndependentEnvironmentMethod: String, CaseIterable {
        case clone
        case copy
    }

    struct LinkedEnvironmentSubmoduleOptions: Sendable {
        let initialize: Bool
        let recursive: Bool
        let paths: [String]
        let matchBranchToEnvironment: Bool

        nonisolated static let disabled = LinkedEnvironmentSubmoduleOptions(
            initialize: false,
            recursive: true,
            paths: [],
            matchBranchToEnvironment: false
        )
    }

    let viewContext: NSManagedObjectContext
    let container: NSPersistentContainer
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "WorkspaceRepositoryStore")

    // Domain services (using libgit2)
    let statusService = GitStatusService()
    let branchService = GitBranchService()
    let worktreeService = GitWorktreeService()
    let remoteService = GitRemoteService()
    let submoduleService = GitSubmoduleService()
    let fileSystemManager: RepositoryFileSystemManager
    let postCreateExecutor = PostCreateActionExecutor()

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.container = PersistenceController.shared.container
        self.fileSystemManager = RepositoryFileSystemManager()
    }
}
