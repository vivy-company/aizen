import AizenCore
import AizenSecurity
import CoreData
import Foundation

public enum AizenStorageModule {}

public enum DurableCommandReceipt: Sendable, Equatable {
    case accepted(DurableCommand)
    case duplicate(DurableCommand)
    case conflict(DurableCommand)
}

public struct StorageSnapshot: Codable, Sendable, Hashable {
    public static let schemaVersion = 2
    public var schemaVersion: Int
    public var spaces: [Space]
    public var sessions: [Session]
    public var conversationMessages: [ConversationMessage]
    public var resources: [Resource]
    public var executionContexts: [ExecutionContext]
    public var terminalSessions: [TerminalSession]
    public var runs: [Run]
    public var operations: [AizenCore.Operation]
    public var operationLogChunks: [OperationLogChunk]
    public var artifacts: [Artifact]
    public var commands: [DurableCommand]
    public var journalEvents: [JournalEvent]
    public var pairingTokens: [PairingTokenRecord]
    public var deviceAuthorizations: [DeviceAuthorization]
    public var securityAuditRecords: [SecurityAuditRecord]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        spaces: [Space] = [], sessions: [Session] = [], conversationMessages: [ConversationMessage] = [], resources: [Resource] = [],
        executionContexts: [ExecutionContext] = [], terminalSessions: [TerminalSession] = [], runs: [Run] = [], operations: [AizenCore.Operation] = [], operationLogChunks: [OperationLogChunk] = [], artifacts: [Artifact] = [], commands: [DurableCommand] = [], journalEvents: [JournalEvent] = [], pairingTokens: [PairingTokenRecord] = [], deviceAuthorizations: [DeviceAuthorization] = [], securityAuditRecords: [SecurityAuditRecord] = []
    ) {
        precondition(schemaVersion == Self.schemaVersion, "Storage snapshots must use schema v2")
        self.schemaVersion = schemaVersion
        self.spaces = spaces
        self.sessions = sessions
        self.conversationMessages = conversationMessages
        self.resources = resources
        self.executionContexts = executionContexts
        self.terminalSessions = terminalSessions
        self.runs = runs
        self.operations = operations
        self.operationLogChunks = operationLogChunks
        self.artifacts = artifacts
        self.commands = commands
        self.journalEvents = journalEvents
        self.pairingTokens = pairingTokens
        self.deviceAuthorizations = deviceAuthorizations
        self.securityAuditRecords = securityAuditRecords
    }

    public var isEmpty: Bool {
        spaces.isEmpty && sessions.isEmpty && conversationMessages.isEmpty && resources.isEmpty && executionContexts.isEmpty &&
            terminalSessions.isEmpty && runs.isEmpty && operations.isEmpty && operationLogChunks.isEmpty && artifacts.isEmpty && commands.isEmpty && journalEvents.isEmpty && pairingTokens.isEmpty && deviceAuthorizations.isEmpty && securityAuditRecords.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, spaces, sessions, conversationMessages, resources, executionContexts, terminalSessions, runs, operations, operationLogChunks, artifacts, commands, journalEvents, pairingTokens, deviceAuthorizations, securityAuditRecords
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        spaces = try values.decode([Space].self, forKey: .spaces)
        sessions = try values.decode([Session].self, forKey: .sessions)
        conversationMessages = try values.decodeIfPresent([ConversationMessage].self, forKey: .conversationMessages) ?? []
        resources = try values.decode([Resource].self, forKey: .resources)
        executionContexts = try values.decode([ExecutionContext].self, forKey: .executionContexts)
        terminalSessions = try values.decodeIfPresent([TerminalSession].self, forKey: .terminalSessions) ?? []
        runs = try values.decode([Run].self, forKey: .runs)
        operations = try values.decode([AizenCore.Operation].self, forKey: .operations)
        operationLogChunks = try values.decodeIfPresent([OperationLogChunk].self, forKey: .operationLogChunks) ?? []
        artifacts = try values.decode([Artifact].self, forKey: .artifacts)
        commands = try values.decodeIfPresent([DurableCommand].self, forKey: .commands) ?? []
        journalEvents = try values.decodeIfPresent([JournalEvent].self, forKey: .journalEvents) ?? []
        pairingTokens = try values.decodeIfPresent([PairingTokenRecord].self, forKey: .pairingTokens) ?? []
        deviceAuthorizations = try values.decodeIfPresent([DeviceAuthorization].self, forKey: .deviceAuthorizations) ?? []
        securityAuditRecords = try values.decodeIfPresent([SecurityAuditRecord].self, forKey: .securityAuditRecords) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(spaces, forKey: .spaces)
        try values.encode(sessions, forKey: .sessions)
        try values.encode(conversationMessages, forKey: .conversationMessages)
        try values.encode(resources, forKey: .resources)
        try values.encode(executionContexts, forKey: .executionContexts)
        try values.encode(terminalSessions, forKey: .terminalSessions)
        try values.encode(runs, forKey: .runs)
        try values.encode(operations, forKey: .operations)
        try values.encode(operationLogChunks, forKey: .operationLogChunks)
        try values.encode(artifacts, forKey: .artifacts)
        try values.encode(commands, forKey: .commands)
        try values.encode(journalEvents, forKey: .journalEvents)
        try values.encode(pairingTokens, forKey: .pairingTokens)
        try values.encode(deviceAuthorizations, forKey: .deviceAuthorizations)
        try values.encode(securityAuditRecords, forKey: .securityAuditRecords)
    }
}

public enum StorageError: Error, Sendable, Equatable {
    case unsupportedSchema(Int)
    case duplicateIdentity(String)
    case missingSpace
    case missingSession
    case missingRun
    case missingResource
    case missingExecutionContext
    case missingOperation
    case missingCommand
    case invalidCommandTransition
    case invalidCommandResult
    case eventCursorExhausted
    case invalidEventRetention
    case invalidOperationLogRetention
    case invalidOperationLogReadLimit
    case operationLogSequenceExhausted
    case migrationDestinationNotEmpty
}

public struct MigrationReport: Codable, Sendable, Hashable {
    public var migratedSpaces = 0
    public var migratedResources = 0
    public var migratedContexts = 0
    public var migratedSessions = 0
    public var skippedRecords = 0
    public var backupURLs: [URL] = []

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
        var report = MigrationReport()
        report.backupURLs = try backupLegacyStore(at: sourceStoreURL, into: backupDirectory)

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
            let path = (repository.value(forKey: "path") as? String).flatMap(normalizedLocalPath)
            let reference = path.map { "local-repository:\($0)" } ?? "legacy-repository-\(id.uuidString)"
            let resource = Resource(id: ResourceID(rawValue: id), spaceID: space.id, kind: .repository, title: name, details: .repository(.init(hostReference: .init(rawValue: reference))))
            snapshot.resources.append(resource); resourceIDs[id] = resource.id; report.migratedResources += 1
        }
        for worktree in worktrees {
            guard let id = worktree.value(forKey: "id") as? UUID else { report.skippedRecords += 1; continue }
            let repositoryID = ((worktree.value(forKey: "repository") as? NSManagedObject)?.value(forKey: "id")) as? UUID
            let resourceID = repositoryID.flatMap { resourceIDs[$0] }
            let spaceID = resourceID.flatMap { id in snapshot.resources.first(where: { $0.id == id })?.spaceID } ?? fallbackSpace.id
            let kind: ExecutionContextKind = (worktree.value(forKey: "isPrimary") as? Bool) == true ? .repositoryCheckout : .gitWorktree
            let path = (worktree.value(forKey: "path") as? String).flatMap(normalizedLocalPath)
            let reference = path.map {
                kind == .gitWorktree ? "local-worktree:\($0)" : "local-checkout:\($0)"
            } ?? "legacy-worktree-\(id.uuidString)"
            let migrated = ExecutionContext(id: ExecutionContextID(rawValue: id), spaceID: spaceID, kind: kind, resourceID: resourceID, hostReference: .init(rawValue: reference))
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
        _ = try await destination.replaceEmpty(with: snapshot)
        return report
    }

    private static func normalizedLocalPath(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func backupLegacyStore(at sourceStoreURL: URL, into backupDirectory: URL, fileManager: FileManager = .default) throws -> [URL] {
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let name = "aizen-1x-\(UUID().uuidString)"
        let sidecars = ["", "-wal", "-shm"]
        var backups: [URL] = []
        for suffix in sidecars {
            let source = URL(fileURLWithPath: sourceStoreURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = backupDirectory.appendingPathComponent(name + ".sqlite" + suffix)
            try fileManager.copyItem(at: source, to: destination)
            backups.append(destination)
        }
        guard !backups.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        return backups
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

    /// Migration has a single writer and may only replace an untouched v2 store.
    public func replaceEmpty(with replacement: StorageSnapshot) throws -> StorageSnapshot {
        try transact { snapshot in
            guard snapshot.isEmpty else { throw StorageError.migrationDestinationNotEmpty }
            snapshot = replacement
        }
    }

    /// Atomically records a Client command before the Host begins non-repeatable side effects.
    public func acceptCommand(_ command: DurableCommand) throws -> DurableCommandReceipt {
        var inserted = false
        let snapshot = try transact { snapshot in
            guard !snapshot.commands.contains(where: { $0.id == command.id }) else { return }
            snapshot.commands.append(command)
            inserted = true
        }
        guard let stored = snapshot.commands.first(where: { $0.id == command.id }) else {
            throw StorageError.duplicateIdentity("command")
        }
        if stored.payloadDigest != command.payloadDigest { return .conflict(stored) }
        return inserted ? .accepted(stored) : .duplicate(stored)
    }

    public func transitionCommand(id: CommandID, to lifecycle: CommandLifecycle, result: DurableCommandResult? = nil) throws -> DurableCommand {
        guard lifecycle != .succeeded || result != nil else { throw StorageError.invalidCommandResult }
        guard lifecycle == .succeeded || result == nil else { throw StorageError.invalidCommandResult }
        let snapshot = try transact { snapshot in
            guard let index = snapshot.commands.firstIndex(where: { $0.id == id }) else { throw StorageError.missingCommand }
            guard snapshot.commands[index].lifecycle.canTransition(to: lifecycle) else { throw StorageError.invalidCommandTransition }
            snapshot.commands[index].lifecycle = lifecycle
            snapshot.commands[index].result = result
            if lifecycle == .executing { snapshot.commands[index].startedAt = Date() }
            if lifecycle == .succeeded || lifecycle == .failed || lifecycle == .cancelled {
                snapshot.commands[index].completedAt = Date()
            }
        }
        guard let command = snapshot.commands.first(where: { $0.id == id }) else { throw StorageError.missingCommand }
        return command
    }

    public func appendJournalEvent(
        spaceID: SpaceID? = nil,
        aggregateID: String,
        aggregateType: String,
        aggregateRevision: UInt64,
        payloadIdentifier: String,
        payloadSchemaVersion: UInt32,
        payloadBytes: Data,
        durability: EventDurability
    ) throws -> JournalEvent {
        let snapshot = try transact { snapshot in
            let cursor = (snapshot.journalEvents.last?.cursor ?? 0)
            guard cursor < UInt64.max else { throw StorageError.eventCursorExhausted }
            snapshot.journalEvents.append(JournalEvent(
                cursor: cursor + 1,
                spaceID: spaceID,
                aggregateID: aggregateID,
                aggregateType: aggregateType,
                aggregateRevision: aggregateRevision,
                payloadIdentifier: payloadIdentifier,
                payloadSchemaVersion: payloadSchemaVersion,
                payloadBytes: payloadBytes,
                durability: durability
            ))
        }
        guard let event = snapshot.journalEvents.last else { throw StorageError.eventCursorExhausted }
        return event
    }

    public func journalEvents(after cursor: UInt64, spaceID: SpaceID? = nil) throws -> [JournalEvent] {
        try load().journalEvents.filter { $0.cursor > cursor && (spaceID == nil || $0.spaceID == nil || $0.spaceID == spaceID) }
    }

    public func journalCursorBounds() throws -> (oldest: UInt64?, latest: UInt64) {
        let events = try load().journalEvents
        return (events.first?.cursor, events.last?.cursor ?? 0)
    }

    /// Appends process output atomically while retaining a bounded tail for each operation.
    /// Callers provide already bounded chunks from their runtime adapter.
    public func appendOperationLogChunk(
        operationID: OperationID,
        stream: OperationLogChunk.Stream,
        text: String,
        retainingAtMost maximumBytes: Int = 1_024 * 1_024
    ) throws -> OperationLogChunk {
        guard maximumBytes >= OperationLogChunk.maximumTextUTF8Count else { throw StorageError.invalidOperationLogRetention }
        var appended: OperationLogChunk?
        _ = try transact { snapshot in
            guard snapshot.operations.contains(where: { $0.id == operationID }) else { throw StorageError.missingOperation }
            let existing = snapshot.operationLogChunks.filter { $0.operationID == operationID }
            guard let sequence = existing.last?.sequence.addingReportingOverflow(1), !sequence.overflow else {
                if existing.isEmpty {
                    let chunk = OperationLogChunk(operationID: operationID, sequence: 1, stream: stream, text: text)
                    snapshot.operationLogChunks.append(chunk)
                    appended = chunk
                    return
                }
                throw StorageError.operationLogSequenceExhausted
            }
            let chunk = OperationLogChunk(operationID: operationID, sequence: sequence.partialValue, stream: stream, text: text)
            snapshot.operationLogChunks.append(chunk)
            var retainedBytes = existing.reduce(0) { $0 + $1.text.utf8.count } + text.utf8.count
            while retainedBytes > maximumBytes,
                  let index = snapshot.operationLogChunks.firstIndex(where: { $0.operationID == operationID }) {
                retainedBytes -= snapshot.operationLogChunks.remove(at: index).text.utf8.count
            }
            appended = chunk
        }
        guard let appended else { throw StorageError.missingOperation }
        return appended
    }

    public func operationLogChunks(operationID: OperationID, afterSequence: UInt64 = 0, maximumBytes: Int = 256 * 1_024) throws -> [OperationLogChunk] {
        guard (1...1_024 * 1_024).contains(maximumBytes) else { throw StorageError.invalidOperationLogReadLimit }
        let chunks = try load().operationLogChunks.filter { $0.operationID == operationID && $0.sequence > afterSequence }
        var remaining = maximumBytes
        var page: [OperationLogChunk] = []
        for chunk in chunks {
            let count = chunk.text.utf8.count
            guard count <= remaining else { break }
            page.append(chunk)
            remaining -= count
        }
        return page
    }

    public func saveDeviceAuthorization(_ authorization: DeviceAuthorization) throws {
        _ = try transact { snapshot in
            snapshot.deviceAuthorizations.removeAll { $0.device.deviceID == authorization.device.deviceID }
            snapshot.deviceAuthorizations.append(authorization)
        }
    }

    public func deviceAuthorization(for deviceID: DeviceID) throws -> DeviceAuthorization? {
        try load().deviceAuthorizations.first { $0.device.deviceID == deviceID }
    }

    public func deviceAuthorizations() throws -> [DeviceAuthorization] {
        try load().deviceAuthorizations
    }

    public func issuePairingToken(_ token: PairingTokenRecord) throws {
        _ = try transact { snapshot in
            guard !snapshot.pairingTokens.contains(where: { $0.tokenID == token.tokenID }) else {
                throw StorageError.duplicateIdentity("pairing token")
            }
            snapshot.pairingTokens.append(token)
        }
    }

    /// Verifies an invitation proof without consuming it so the Host can show only valid pairing requests.
    public func validatePairingToken(tokenID: UUID, secret: Data, now: Date = Date()) throws {
        enum Result { case valid, unknown, expired, rejected }
        var result: Result = .unknown
        _ = try transact { snapshot in
            guard let index = snapshot.pairingTokens.firstIndex(where: { $0.tokenID == tokenID }) else { return }
            let token = snapshot.pairingTokens[index]
            guard token.expiresAt > now else {
                snapshot.pairingTokens.remove(at: index)
                result = .expired
                return
            }
            result = token.proof.matches(secret) ? .valid : .rejected
        }
        switch result {
        case .valid: return
        case .unknown: throw SecurityError.pairingTokenUnknown
        case .expired: throw SecurityError.invitationExpired
        case .rejected: throw SecurityError.pairingTokenRejected
        }
    }

    /// Atomically consumes a valid invitation proof and makes its authorization effective.
    public func approvePairing(
        tokenID: UUID,
        secret: Data,
        authorization: DeviceAuthorization,
        auditRecord: SecurityAuditRecord,
        now: Date = Date()
    ) throws {
        enum Result { case approved, unknown, expired, rejected }
        var result: Result = .unknown
        _ = try transact { snapshot in
            guard let index = snapshot.pairingTokens.firstIndex(where: { $0.tokenID == tokenID }) else { return }
            let token = snapshot.pairingTokens[index]
            guard token.expiresAt > now else {
                snapshot.pairingTokens.remove(at: index)
                result = .expired
                return
            }
            guard token.proof.matches(secret) else {
                result = .rejected
                return
            }
            snapshot.pairingTokens.remove(at: index)
            snapshot.deviceAuthorizations.removeAll { $0.device.deviceID == authorization.device.deviceID }
            snapshot.deviceAuthorizations.append(authorization)
            snapshot.securityAuditRecords.append(auditRecord)
            result = .approved
        }
        switch result {
        case .approved: return
        case .unknown: throw SecurityError.pairingTokenUnknown
        case .expired: throw SecurityError.invitationExpired
        case .rejected: throw SecurityError.pairingTokenRejected
        }
    }

    public func appendSecurityAuditRecord(_ record: SecurityAuditRecord) throws {
        _ = try transact { $0.securityAuditRecords.append(record) }
    }

    public func pruneJournalEvents(keepingMostRecent retention: Int) throws -> Int {
        guard retention >= 0 else { throw StorageError.invalidEventRetention }
        var removed = 0
        _ = try transact { snapshot in
            let count = snapshot.journalEvents.count
            guard count > retention else { return }
            removed = count - retention
            snapshot.journalEvents.removeFirst(removed)
        }
        return removed
    }

    private func validate(_ snapshot: StorageSnapshot) throws {
        let spaceIDs = Set(snapshot.spaces.map(\.id))
        guard spaceIDs.count == snapshot.spaces.count else { throw StorageError.duplicateIdentity("space") }
        guard snapshot.sessions.allSatisfy({ spaceIDs.contains($0.spaceID) }) else { throw StorageError.missingSpace }
        guard Set(snapshot.sessions.map(\.id)).count == snapshot.sessions.count else { throw StorageError.duplicateIdentity("session") }
        guard Set(snapshot.conversationMessages.map(\.id)).count == snapshot.conversationMessages.count else { throw StorageError.duplicateIdentity("conversation message") }
        guard Set(snapshot.resources.map(\.id)).count == snapshot.resources.count else { throw StorageError.duplicateIdentity("resource") }
        guard Set(snapshot.executionContexts.map(\.id)).count == snapshot.executionContexts.count else { throw StorageError.duplicateIdentity("execution context") }
        guard Set(snapshot.terminalSessions.map(\.id)).count == snapshot.terminalSessions.count else { throw StorageError.duplicateIdentity("terminal session") }
        guard Set(snapshot.runs.map(\.id)).count == snapshot.runs.count else { throw StorageError.duplicateIdentity("run") }
        guard Set(snapshot.operations.map(\.id)).count == snapshot.operations.count else { throw StorageError.duplicateIdentity("operation") }
        guard Set(snapshot.commands.map(\.id)).count == snapshot.commands.count else { throw StorageError.duplicateIdentity("command") }
        guard Set(snapshot.journalEvents.map(\.id)).count == snapshot.journalEvents.count else { throw StorageError.duplicateIdentity("journal event") }
        guard Set(snapshot.pairingTokens.map(\.tokenID)).count == snapshot.pairingTokens.count else { throw StorageError.duplicateIdentity("pairing token") }
        guard Set(snapshot.deviceAuthorizations.map(\.device.deviceID)).count == snapshot.deviceAuthorizations.count else { throw StorageError.duplicateIdentity("device authorization") }
        guard Set(snapshot.securityAuditRecords.map(\.id)).count == snapshot.securityAuditRecords.count else { throw StorageError.duplicateIdentity("security audit record") }
        guard zip(snapshot.journalEvents, snapshot.journalEvents.dropFirst()).allSatisfy({ $0.cursor < $1.cursor }) else { throw StorageError.duplicateIdentity("journal cursor") }
        guard snapshot.resources.allSatisfy({ spaceIDs.contains($0.spaceID) }) else { throw StorageError.missingSpace }
        guard snapshot.executionContexts.allSatisfy({ spaceIDs.contains($0.spaceID) }) else { throw StorageError.missingSpace }
        guard snapshot.terminalSessions.allSatisfy({ spaceIDs.contains($0.spaceID) }) else { throw StorageError.missingSpace }

        let sessions = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0) })
        let resources = Dictionary(uniqueKeysWithValues: snapshot.resources.map { ($0.id, $0) })
        let contexts = Dictionary(uniqueKeysWithValues: snapshot.executionContexts.map { ($0.id, $0) })
        guard snapshot.executionContexts.allSatisfy({ context in
            guard let resourceID = context.resourceID else { return true }
            guard let resource = resources[resourceID] else { return false }
            return resource.spaceID == context.spaceID
        }) else { throw StorageError.missingResource }
        guard snapshot.sessions.allSatisfy({ session in
            guard let contextID = session.executionContextID else { return true }
            guard let context = contexts[contextID] else { return false }
            return context.spaceID == session.spaceID
        }) else { throw StorageError.missingExecutionContext }
        guard snapshot.terminalSessions.allSatisfy({ session in
            guard let contextID = session.executionContextID else { return true }
            guard let context = contexts[contextID] else { return false }
            return context.spaceID == session.spaceID
        }) else { throw StorageError.missingExecutionContext }
        guard snapshot.conversationMessages.allSatisfy({ message in
            guard let session = sessions[message.sessionID] else { return false }
            return session.spaceID == message.spaceID
        }) else { throw StorageError.missingSession }
        let runs = Dictionary(uniqueKeysWithValues: snapshot.runs.map { ($0.id, $0) })
        let operations = Dictionary(uniqueKeysWithValues: snapshot.operations.map { ($0.id, $0) })
        guard snapshot.operationLogChunks.allSatisfy({ operations[$0.operationID] != nil }) else { throw StorageError.missingOperation }
        let operationLogs = Dictionary(grouping: snapshot.operationLogChunks, by: \.operationID)
        guard operationLogs.values.allSatisfy({ chunks in zip(chunks, chunks.dropFirst()).allSatisfy { $0.sequence < $1.sequence } }) else {
            throw StorageError.duplicateIdentity("operation log sequence")
        }
        guard snapshot.conversationMessages.allSatisfy({ message in
            guard let runID = message.runID else { return true }
            guard let run = runs[runID] else { return false }
            return run.spaceID == message.spaceID && run.sessionID == message.sessionID
        }) else { throw StorageError.missingRun }
        guard snapshot.runs.allSatisfy({ run in
            guard let session = sessions[run.sessionID], session.spaceID == run.spaceID else { return false }
            guard let contextID = run.executionContextID else { return true }
            guard let context = contexts[contextID] else { return false }
            return context.spaceID == run.spaceID
        }) else { throw StorageError.missingSession }
    }
}
