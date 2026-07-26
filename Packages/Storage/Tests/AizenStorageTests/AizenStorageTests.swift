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

@Test func repositoryPersistsCanonicalConversationMessages() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    let session = Session(spaceID: space.id, kind: .conversation, title: "No repository needed")
    let message = ConversationMessage(spaceID: space.id, sessionID: session.id, role: .user, content: "Hello")
    _ = try await repository.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
        $0.conversationMessages.append(message)
    }
    #expect(try await repository.load().conversationMessages == [message])
}

@Test func snapshotDecodesExistingV2FilesWithoutMessages() throws {
    let snapshot = StorageSnapshot()
    let oldFormat = """
    {"schemaVersion":2,"spaces":[],"sessions":[],"resources":[],"executionContexts":[],"runs":[],"operations":[],"artifacts":[]}
    """
    let decoded = try JSONDecoder().decode(StorageSnapshot.self, from: Data(oldFormat.utf8))
    #expect(decoded == snapshot)
}

@Test func repositoryAcceptsDurableCommandsExactlyOnce() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    _ = try await repository.transact { $0.spaces.append(space) }
    let command = DurableCommand(spaceID: space.id, payloadDigest: "sha256:one")
    #expect(try await repository.acceptCommand(command) == .accepted(command))
    #expect(try await repository.acceptCommand(command) == .duplicate(command))
    let conflicting = DurableCommand(id: command.id, spaceID: space.id, payloadDigest: "sha256:two")
    #expect(try await repository.acceptCommand(conflicting) == .conflict(command))
    _ = try await repository.transitionCommand(id: command.id, to: .executing)
    let result = DurableCommandResult(payloadIdentifier: "aizen.command-result.example@1", schemaVersion: 1, protobufBytes: Data([1]))
    let completed = try await repository.transitionCommand(id: command.id, to: .succeeded, result: result)
    #expect(completed.result == result)
    #expect(try await repository.load().commands == [completed])
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
