//
//  Persistence.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import CoreData
import os.log

struct PersistenceController {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "Persistence")
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample workspaces
        let personalWorkspace = Workspace(context: viewContext)
        personalWorkspace.id = UUID()
        personalWorkspace.name = "Personal"
        personalWorkspace.order = 0

        let workWorkspace = Workspace(context: viewContext)
        workWorkspace.id = UUID()
        workWorkspace.name = "Work"
        workWorkspace.order = 1

        // Create sample repository
        let sampleRepo = Repository(context: viewContext)
        sampleRepo.id = UUID()
        sampleRepo.name = "sample-project"
        sampleRepo.path = "/Users/sample/projects/sample-project"
        sampleRepo.workspace = personalWorkspace
        sampleRepo.lastUpdated = Date()

        // Create sample worktrees
        let mainWorktree = Worktree(context: viewContext)
        mainWorktree.id = UUID()
        mainWorktree.path = "/Users/sample/projects/sample-project"
        mainWorktree.branch = "main"
        mainWorktree.isPrimary = true
        mainWorktree.repository = sampleRepo

        let featureWorktree = Worktree(context: viewContext)
        featureWorktree.id = UUID()
        featureWorktree.path = "/Users/sample/projects/sample-project-feature"
        featureWorktree.branch = "feature/new-ui"
        featureWorktree.isPrimary = false
        featureWorktree.repository = sampleRepo

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "aizen")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Create default workspace if none exists
        if !inMemory {
            createDefaultWorkspaceIfNeeded()
        }
    }

    private func createDefaultWorkspaceIfNeeded() {
        let fetchRequest: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        fetchRequest.fetchLimit = 1

        do {
            let count = try container.viewContext.count(for: fetchRequest)
            if count == 0 {
                let defaultWorkspace = Workspace(context: container.viewContext)
                defaultWorkspace.id = UUID()
                defaultWorkspace.name = "Default"
                defaultWorkspace.order = 0

                try container.viewContext.save()
            }
        } catch {
            logger.error("Failed to create default workspace: \(error)")
        }
    }
}
