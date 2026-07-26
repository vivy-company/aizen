import Foundation
import Testing
import AizenCore
import AizenSecurity
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

@Test func repositoryPersistsHostOwnedTerminalSessions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    let terminal = TerminalSession(
        spaceID: space.id,
        title: "Shell",
        tmuxSessionName: "aizen-pane",
        paneID: "pane"
    )
    _ = try await repository.transact {
        $0.spaces.append(space)
        $0.terminalSessions.append(terminal)
    }
    #expect(try await repository.load().terminalSessions == [terminal])
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

@Test func repositoryPersistsAuthorizationAndContentFreeSecurityAudit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let device = DevicePublicIdentity(
        deviceID: DeviceID(),
        displayName: "Phone",
        platform: "iOS",
        cryptographicIdentity: LocalCryptographicIdentity().publicIdentity()
    )
    let authorization = DeviceAuthorization(device: device, grants: [CapabilityGrant(capability: .spaceRead)])

    try await repository.saveDeviceAuthorization(authorization)
    try await repository.appendSecurityAuditRecord(SecurityAuditRecord(kind: .pairingApproved, deviceID: device.deviceID, route: "lan"))

    #expect(try await repository.deviceAuthorization(for: device.deviceID) == authorization)
    #expect(try await repository.load().securityAuditRecords.map(\.kind) == [.pairingApproved])
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
    let startedAt = try #require(completed.startedAt)
    let completedAt = try #require(completed.completedAt)
    #expect(completed.acceptedAt <= startedAt)
    #expect(startedAt <= completedAt)
    #expect(try await repository.load().commands == [completed])

    let secondCommand = DurableCommand(spaceID: space.id, payloadDigest: "sha256:three")
    _ = try await repository.acceptCommand(secondCommand)
    await #expect(throws: StorageError.invalidCommandResult) {
        try await repository.transitionCommand(id: secondCommand.id, to: .executing, result: result)
    }
}

@Test func durableCommandReceiptsOutliveDeletedSpaces() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    let command = DurableCommand(spaceID: space.id, payloadDigest: "sha256:one")
    _ = try await repository.transact {
        $0.spaces.append(space)
        $0.commands.append(command)
    }
    _ = try await repository.transact { $0.spaces.removeAll(where: { $0.id == space.id }) }
    #expect(try await repository.load().commands == [command])
}

@Test func repositoryReplaysBoundedScopedJournalEvents() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    _ = try await repository.transact { $0.spaces.append(space) }
    let hostEvent = try await repository.appendJournalEvent(
        aggregateID: "host",
        aggregateType: "host",
        aggregateRevision: 1,
        payloadIdentifier: "aizen.event.host@1",
        payloadSchemaVersion: 1,
        payloadBytes: Data([1]),
        durability: .durable
    )
    let spaceEvent = try await repository.appendJournalEvent(
        spaceID: space.id,
        aggregateID: space.id.description,
        aggregateType: "space",
        aggregateRevision: 1,
        payloadIdentifier: "aizen.event.space@1",
        payloadSchemaVersion: 1,
        payloadBytes: Data([2]),
        durability: .durable
    )
    #expect(hostEvent.cursor == 1)
    #expect(spaceEvent.cursor == 2)
    #expect(try await repository.journalEvents(after: 0, spaceID: space.id).map(\.cursor) == [1, 2])
    #expect(try await repository.journalEvents(after: 1, spaceID: space.id) == [spaceEvent])
    #expect(try await repository.journalCursorBounds().latest == 2)
    #expect(try await repository.pruneJournalEvents(keepingMostRecent: 1) == 1)
    #expect(try await repository.journalCursorBounds().oldest == 2)
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
