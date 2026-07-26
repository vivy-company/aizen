import AizenCore
import CoreData
import Foundation

public enum AizenStorageModule {}

public struct StorageSnapshot: Codable, Sendable, Hashable {
    public static let schemaVersion = 2
    public var schemaVersion: Int
    public var spaces: [Space]
    public var sessions: [Session]
    public var resources: [Resource]
    public var executionContexts: [ExecutionContext]
    public var runs: [Run]
    public var operations: [AizenCore.Operation]
    public var artifacts: [Artifact]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        spaces: [Space] = [], sessions: [Session] = [], resources: [Resource] = [],
        executionContexts: [ExecutionContext] = [], runs: [Run] = [], operations: [AizenCore.Operation] = [], artifacts: [Artifact] = []
    ) {
        precondition(schemaVersion == Self.schemaVersion, "Storage snapshots must use schema v2")
        self.schemaVersion = schemaVersion
        self.spaces = spaces
        self.sessions = sessions
        self.resources = resources
        self.executionContexts = executionContexts
        self.runs = runs
        self.operations = operations
        self.artifacts = artifacts
    }
}

public enum StorageError: Error, Sendable, Equatable {
    case unsupportedSchema(Int)
    case duplicateIdentity(String)
    case missingSpace
}

public struct MigrationReport: Codable, Sendable, Hashable {
    public var migratedSpaces = 0
    public var migratedResources = 0
    public var migratedContexts = 0
    public var migratedSessions = 0
    public var skippedRecords = 0

    public init() {}
}

/// Imports the meaningful, durable part of the 1.x Core Data graph. The old store is opened read-only;
/// paths and credentials remain Host-private references in v2.
public enum LegacyCoreDataMigration {
    public static func migrate(
        sourceStoreURL: URL,
        legacyModelURL: URL,
        destination: StorageRepository,
        backupDirectory: URL
    ) async throws -> MigrationReport {
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backupURL = backupDirectory.appendingPathComponent("aizen-1x-\(Int(Date().timeIntervalSince1970)).sqlite")
        try FileManager.default.copyItem(at: sourceStoreURL, to: backupURL)

        guard let model = NSManagedObjectModel(contentsOf: legacyModelURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let container = NSPersistentContainer(name: "AizenLegacyImport", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: sourceStoreURL)
        description.isReadOnly = true
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }

        let context = container.viewContext
        let workspaces = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Workspace"))
        let repositories = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Repository"))
        let worktrees = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Worktree"))
        let chats = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ChatSession"))

        var report = MigrationReport()
        let defaultSpace = Space(name: "Personal")
        var spaces = Dictionary(uniqueKeysWithValues: workspaces.compactMap { workspace -> (UUID, Space)? in
            guard let legacyID = workspace.value(forKey: "id") as? UUID,
                  let name = workspace.value(forKey: "name") as? String, !name.isEmpty else { return nil }
            report.migratedSpaces += 1
            return (legacyID, Space(id: SpaceID(rawValue: legacyID), name: name, icon: workspace.value(forKey: "colorHex") as? String))
        })
        if spaces.isEmpty { spaces[UUID()] = defaultSpace; report.migratedSpaces += 1 }
        let fallbackSpace = spaces.values.sorted { $0.id.description < $1.id.description }.first ?? defaultSpace
        var resourceIDs = [UUID: ResourceID]()
        var contextIDs = [UUID: ExecutionContextID]()
        var snapshot = StorageSnapshot(spaces: Array(spaces.values))

        for repository in repositories {
            guard let id = repository.value(forKey: "id") as? UUID,
                  let name = repository.value(forKey: "name") as? String else { report.skippedRecords += 1; continue }
            let workspaceID = (repository.value(forKey: "workspace") as? NSManagedObject)?.value(forKey: "id") as? UUID
            let space = workspaceID.flatMap { spaces[$0] } ?? fallbackSpace
            let resource = Resource(id: ResourceID(rawValue: id), spaceID: space.id, kind: .repository, title: name, details: .repository(.init(hostReference: .init(rawValue: "legacy-repository-\(id.uuidString)"))))
            snapshot.resources.append(resource); resourceIDs[id] = resource.id; report.migratedResources += 1
        }
        for worktree in worktrees {
            guard let id = worktree.value(forKey: "id") as? UUID else { report.skippedRecords += 1; continue }
            let repositoryID = ((worktree.value(forKey: "repository") as? NSManagedObject)?.value(forKey: "id")) as? UUID
            let resourceID = repositoryID.flatMap { resourceIDs[$0] }
            let spaceID = resourceID.flatMap { id in snapshot.resources.first(where: { $0.id == id })?.spaceID } ?? fallbackSpace.id
            let kind: ExecutionContextKind = (worktree.value(forKey: "isPrimary") as? Bool) == true ? .repositoryCheckout : .gitWorktree
            let migrated = ExecutionContext(id: ExecutionContextID(rawValue: id), spaceID: spaceID, kind: kind, resourceID: resourceID, hostReference: .init(rawValue: "legacy-worktree-\(id.uuidString)"))
            snapshot.executionContexts.append(migrated); contextIDs[id] = migrated.id; report.migratedContexts += 1
        }
        for chat in chats {
            guard let id = chat.value(forKey: "id") as? UUID else { report.skippedRecords += 1; continue }
            let worktreeID = ((chat.value(forKey: "worktree") as? NSManagedObject)?.value(forKey: "id")) as? UUID
            let contextID = worktreeID.flatMap { contextIDs[$0] }
            let spaceID = contextID.flatMap { id in snapshot.executionContexts.first(where: { $0.id == id })?.spaceID } ?? fallbackSpace.id
            let title = (chat.value(forKey: "title") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Conversation"
            snapshot.sessions.append(Session(id: SessionID(rawValue: id), spaceID: spaceID, kind: .conversation, title: title, lifecycle: (chat.value(forKey: "archived") as? Bool) == true ? .archived : .active, executionContextID: contextID))
            report.migratedSessions += 1
        }
        _ = try await destination.transact { $0 = snapshot }
        return report
    }
}

/// Host-owned v2 persistence. It commits a complete semantic snapshot atomically; UI and clients see Core values only.
public actor StorageRepository {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> StorageSnapshot {
        guard fileManager.fileExists(atPath: url.path) else { return StorageSnapshot() }
        let snapshot = try decoder.decode(StorageSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.schemaVersion == StorageSnapshot.schemaVersion else { throw StorageError.unsupportedSchema(snapshot.schemaVersion) }
        try validate(snapshot)
        return snapshot
    }

    public func transact(_ mutation: (inout StorageSnapshot) throws -> Void) throws -> StorageSnapshot {
        var snapshot = try load()
        try mutation(&snapshot)
        try validate(snapshot)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try encoder.encode(snapshot).write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
        return snapshot
    }

    private func validate(_ snapshot: StorageSnapshot) throws {
        let spaceIDs = Set(snapshot.spaces.map(\.id))
        guard spaceIDs.count == snapshot.spaces.count else { throw StorageError.duplicateIdentity("space") }
        guard snapshot.sessions.allSatisfy({ spaceIDs.contains($0.spaceID) }) else { throw StorageError.missingSpace }
    }
}
