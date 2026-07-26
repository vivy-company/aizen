import Foundation
import Testing
import AizenCore
@testable import AizenStorage

@Test func moduleLoads() { _ = AizenStorageModule.self }

@Test func repositoryPersistsProjectlessSessionsAtomically() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    let saved = try await repository.transact { snapshot in
        snapshot.spaces.append(space)
        snapshot.sessions.append(Session(spaceID: space.id, kind: .conversation, title: "No repository needed"))
    }
    #expect(saved.sessions.first?.resourceIDs.isEmpty == true)
    #expect(try await repository.load() == saved)
}

@Test func failedTransactionsLeaveTheLastValidSnapshotIntact() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    _ = try await repository.transact { $0.spaces.append(space) }

    await #expect(throws: StorageError.missingSpace) {
        try await repository.transact {
            $0.sessions.append(Session(spaceID: SpaceID(), kind: .conversation, title: "Invalid containment"))
        }
    }
    #expect(try await repository.load().sessions.isEmpty)
}

@Test func migrationReplacementNeverOverwritesExistingV2Data() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let existingSpace = Space(name: "Existing")
    _ = try await repository.transact { $0.spaces.append(existingSpace) }

    await #expect(throws: StorageError.migrationDestinationNotEmpty) {
        try await repository.replaceEmpty(with: StorageSnapshot(spaces: [Space(name: "Imported")]))
    }
    #expect(try await repository.load().spaces.map(\.name) == ["Existing"])
}

@Test func legacyBackupIncludesSQLiteSidecars() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("aizen.sqlite")
    try Data("store".utf8).write(to: source)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: source.path + "-wal"))
    try Data("shm".utf8).write(to: URL(fileURLWithPath: source.path + "-shm"))

    let backups = try LegacyCoreDataMigration.backupLegacyStore(at: source, into: directory.appendingPathComponent("backup", isDirectory: true))
    #expect(backups.count == 3)
    #expect(Set(try backups.map { try Data(contentsOf: $0) }) == Set([Data("store".utf8), Data("wal".utf8), Data("shm".utf8)]))
}
