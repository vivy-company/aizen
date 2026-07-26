import AizenCore
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
