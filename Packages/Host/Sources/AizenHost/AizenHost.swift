import AizenCore
import AizenStorage
import AizenTransport
import AizenWire
import CryptoKit
import Foundation

/// Host command/query composition. Mac-only runtime adapters stay outside this package.
public enum AizenHostModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
}

/// Explicit local Host composition. It owns Storage but exposes only Wire envelopes and Core snapshots.
public actor LocalHost: WireEndpoint {
    private let storage: StorageRepository
    private let conversationRuns: ConversationRunCoordinator?
    private let managedSandboxes: ManagedSandboxService?
    private let runEventPublisher: RunEventPublisher?

    public init(
        storage: StorageRepository,
        conversationRuns: ConversationRunCoordinator? = nil,
        managedSandboxes: ManagedSandboxService? = nil,
        runEventPublisher: RunEventPublisher? = nil
    ) {
        self.storage = storage
        self.conversationRuns = conversationRuns
        self.managedSandboxes = managedSandboxes
        self.runEventPublisher = runEventPublisher
    }

    public func runEvents() async -> AsyncStream<RunEvent> {
        guard let runEventPublisher else { return AsyncStream { $0.finish() } }
        return await runEventPublisher.events()
    }

    public func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let payload: TypedPayload
        let kind: WireMessageKind
        switch envelope.kind {
        case .hello:
            kind = .capabilities
            payload = try TypedPayload(CapabilitiesPayload(identifiers: [
                HelloPayload.identifier,
                CapabilitiesPayload.identifier,
                SnapshotRequestPayload.identifier,
                SnapshotResponsePayload.identifier,
                ListSpacesQueryPayload.identifier,
                ListSpacesResponsePayload.identifier,
                ListConversationsQueryPayload.identifier,
                ListConversationsResponsePayload.identifier,
                GetConversationTimelineQueryPayload.identifier,
                GetConversationTimelineResponsePayload.identifier,
                ListRunsQueryPayload.identifier,
                ListRunsResponsePayload.identifier,
                ListResourcesQueryPayload.identifier,
                ListResourcesResponsePayload.identifier,
                ListExecutionContextsQueryPayload.identifier,
                ListExecutionContextsResponsePayload.identifier,
                CreateSpaceCommandPayload.identifier,
                CreateSpaceResultPayload.identifier,
                RenameSpaceCommandPayload.identifier,
                DeleteSpaceCommandPayload.identifier,
                SpaceMutationResultPayload.identifier,
                CreateConversationCommandPayload.identifier,
                CreateConversationResultPayload.identifier,
                SendConversationCommandPayload.identifier,
                SendConversationResultPayload.identifier,
                CancelRunCommandPayload.identifier,
                CancelRunResultPayload.identifier,
                ImportLocalFolderCommandPayload.identifier,
                ImportLocalFolderResultPayload.identifier,
                ImportLocalRepositoryCommandPayload.identifier,
                ImportLocalRepositoryResultPayload.identifier,
                RemoveResourceCommandPayload.identifier,
                ResourceMutationResultPayload.identifier,
                CreateLocalFolderContextCommandPayload.identifier,
                CreateLocalFolderContextResultPayload.identifier,
                CreateRepositoryCheckoutContextCommandPayload.identifier,
                CreateRepositoryCheckoutContextResultPayload.identifier,
                AttachExecutionContextCommandPayload.identifier,
                DetachExecutionContextCommandPayload.identifier,
                RemoveExecutionContextCommandPayload.identifier,
                ExecutionContextMutationResultPayload.identifier
            ]))
        case .query where envelope.payload.identifier == SnapshotRequestPayload.identifier:
            let request = try SnapshotRequestPayload(protobufBytes: envelope.payload.protobufBytes)
            let snapshot = try await storage.load()
            kind = .queryResponse
            payload = try TypedPayload(SnapshotResponsePayload(scope: request.scope, cursor: 0, snapshot: JSONEncoder().encode(snapshot)))
        case .query where envelope.payload.identifier == ListSpacesQueryPayload.identifier:
            _ = try ListSpacesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaces = try await storage.load().spaces
            kind = .queryResponse
            payload = try TypedPayload(ListSpacesResponsePayload(spaces: spaces))
        case .query where envelope.payload.identifier == ListConversationsQueryPayload.identifier:
            let query = try ListConversationsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let conversations = try await storage.load().sessions.filter {
                $0.kind == .conversation && (spaceID == nil || $0.spaceID == spaceID)
            }
            kind = .queryResponse
            payload = try TypedPayload(ListConversationsResponsePayload(conversations: conversations))
        case .query where envelope.payload.identifier == GetConversationTimelineQueryPayload.identifier:
            let query = try GetConversationTimelineQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let sessionID = try Self.sessionID(from: query.sessionID)
            let messages = try await storage.load().conversationMessages
                .filter { $0.sessionID == sessionID }
                .sorted { $0.createdAt < $1.createdAt }
            kind = .queryResponse
            payload = try TypedPayload(GetConversationTimelineResponsePayload(messages: messages))
        case .query where envelope.payload.identifier == ListRunsQueryPayload.identifier:
            let query = try ListRunsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let runs = try await storage.load().runs.filter { spaceID == nil || $0.spaceID == spaceID }
            kind = .queryResponse
            payload = try TypedPayload(ListRunsResponsePayload(runs: runs))
        case .query where envelope.payload.identifier == ListResourcesQueryPayload.identifier:
            let query = try ListResourcesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let resources = try await storage.load().resources.filter { spaceID == nil || $0.spaceID == spaceID }
            kind = .queryResponse
            payload = try TypedPayload(ListResourcesResponsePayload(resources: resources))
        case .query where envelope.payload.identifier == ListExecutionContextsQueryPayload.identifier:
            let query = try ListExecutionContextsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let resourceID = try query.resourceID.map(Self.resourceID(from:))
            let contexts = try await storage.load().executionContexts.filter {
                (spaceID == nil || $0.spaceID == spaceID) && (resourceID == nil || $0.resourceID == resourceID)
            }
            kind = .queryResponse
            payload = try TypedPayload(ListExecutionContextsResponsePayload(contexts: contexts))
        case .command where envelope.payload.identifier == CreateSpaceCommandPayload.identifier:
            let command = try CreateSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let space = Space(name: command.name, icon: command.icon, summary: command.summary)
            _ = try await storage.transact { $0.spaces.append(space) }
            kind = .commandResult
            payload = try TypedPayload(CreateSpaceResultPayload(spaceID: space.id.description))
        case .command where envelope.payload.identifier == RenameSpaceCommandPayload.identifier:
            let command = try RenameSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                _ = try await self.storage.transact { snapshot in
                    guard let index = snapshot.spaces.firstIndex(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    snapshot.spaces[index].name = command.name
                }
                return try TypedPayload(SpaceMutationResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == DeleteSpaceCommandPayload.identifier:
            let command = try DeleteSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            _ = try await storage.transact { snapshot in
                guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                guard !snapshot.sessions.contains(where: { $0.spaceID == spaceID }) &&
                    !snapshot.resources.contains(where: { $0.spaceID == spaceID }) &&
                    !snapshot.executionContexts.contains(where: { $0.spaceID == spaceID }) &&
                    !snapshot.runs.contains(where: { $0.spaceID == spaceID }) &&
                    !snapshot.operations.contains(where: { $0.spaceID == spaceID }) &&
                    !snapshot.artifacts.contains(where: { $0.spaceID == spaceID }) else {
                    throw HostProtocolError.spaceNotEmpty(spaceID)
                }
                snapshot.spaces.removeAll(where: { $0.id == spaceID })
            }
            kind = .commandResult
            payload = try TypedPayload(SpaceMutationResultPayload())
        case .command where envelope.payload.identifier == CreateConversationCommandPayload.identifier:
            let command = try CreateConversationCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let session = Session(spaceID: spaceID, kind: .conversation, title: command.title)
                _ = try await self.storage.transact { snapshot in
                    guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    snapshot.sessions.append(session)
                }
                return try TypedPayload(CreateConversationResultPayload(sessionID: session.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == SendConversationCommandPayload.identifier:
            guard let conversationRuns else { throw HostProtocolError.runtimeUnavailable }
            let command = try SendConversationCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let rawSpaceID = UUID(uuidString: command.spaceID),
                let rawSessionID = UUID(uuidString: command.sessionID),
                let rawMessageID = UUID(uuidString: command.messageID),
                let rawRunID = UUID(uuidString: command.runID) else {
                throw HostProtocolError.invalidIdentity("Conversation send")
            }
            let spaceID = SpaceID(rawValue: rawSpaceID)
            let sessionID = SessionID(rawValue: rawSessionID)
            let runID = RunID(rawValue: rawRunID)
            let message = ConversationMessage(
                id: ConversationMessageID(rawValue: rawMessageID),
                spaceID: spaceID,
                sessionID: sessionID,
                role: .user,
                content: command.content
            )
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let executionContextID = try await self.executionContext(for: sessionID, in: spaceID)
                try await conversationRuns.submit(
                    message: message,
                    run: Run(id: runID, spaceID: spaceID, sessionID: sessionID, executionContextID: executionContextID)
                )
                return try TypedPayload(SendConversationResultPayload(runID: runID.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CancelRunCommandPayload.identifier:
            guard let conversationRuns else { throw HostProtocolError.runtimeUnavailable }
            let command = try CancelRunCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let rawRunID = UUID(uuidString: command.runID) else { throw HostProtocolError.invalidIdentity(command.runID) }
            let runID = RunID(rawValue: rawRunID)
            guard let spaceID = try await storage.load().runs.first(where: { $0.id == runID })?.spaceID else {
                throw HostProtocolError.unknownRun(runID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                try await conversationRuns.cancel(runID: runID)
                return try TypedPayload(CancelRunResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == ImportLocalFolderCommandPayload.identifier:
            let command = try ImportLocalFolderCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let directory = try Self.localDirectory(from: command.path)
                let resource = Resource(
                    spaceID: spaceID,
                    kind: .folder,
                    title: command.title ?? directory.lastPathComponent,
                    details: .hostPrivate(HostPrivateReference(rawValue: "local-folder:\(directory.path)"))
                )
                let snapshot = try await self.storage.transact { snapshot in
                    guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    if let existing = snapshot.resources.first(where: { $0.details == resource.details }) {
                        guard existing.spaceID == spaceID else {
                            throw HostProtocolError.duplicateResource(existing.id)
                        }
                        return
                    }
                    snapshot.resources.append(resource)
                }
                guard let importedResource = snapshot.resources.first(where: { $0.details == resource.details }) else {
                    throw HostProtocolError.unknownResource(resource.id)
                }
                return try TypedPayload(ImportLocalFolderResultPayload(resourceID: importedResource.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == ImportLocalRepositoryCommandPayload.identifier:
            let command = try ImportLocalRepositoryCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let directory = try Self.localDirectory(from: command.path)
                guard Self.isGitRepository(directory) else { throw HostProtocolError.invalidResourcePath(directory.path) }
                let resource = Resource(spaceID: spaceID, kind: .repository, title: command.title ?? directory.lastPathComponent, details: .hostPrivate(.init(rawValue: "local-repository:\(directory.path)")))
                let snapshot = try await self.storage.transact { snapshot in
                    guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    if let existing = snapshot.resources.first(where: { $0.details == resource.details }) {
                        guard existing.spaceID == spaceID else { throw HostProtocolError.duplicateResource(existing.id) }
                        return
                    }
                    snapshot.resources.append(resource)
                }
                guard let imported = snapshot.resources.first(where: { $0.details == resource.details }) else { throw HostProtocolError.unknownResource(resource.id) }
                return try TypedPayload(ImportLocalRepositoryResultPayload(resourceID: imported.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == RemoveResourceCommandPayload.identifier:
            let command = try RemoveResourceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let uuid = UUID(uuidString: command.resourceID) else { throw HostProtocolError.invalidIdentity(command.resourceID) }
            let resourceID = ResourceID(rawValue: uuid)
            if let replayed = try await durableReplayResult(for: envelope) {
                payload = replayed
            } else {
                guard let spaceID = try await storage.load().resources.first(where: { $0.id == resourceID })?.spaceID else {
                    throw HostProtocolError.unknownResource(resourceID)
                }
                payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                    _ = try await self.storage.transact { snapshot in
                        guard snapshot.resources.contains(where: { $0.id == resourceID }) else { throw HostProtocolError.unknownResource(resourceID) }
                        guard !snapshot.executionContexts.contains(where: { $0.resourceID == resourceID }) else {
                            throw HostProtocolError.resourceInUse(resourceID)
                        }
                        snapshot.resources.removeAll(where: { $0.id == resourceID })
                    }
                    return try TypedPayload(ResourceMutationResultPayload())
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateLocalFolderContextCommandPayload.identifier:
            let command = try CreateLocalFolderContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            let resourceID = try Self.resourceID(from: command.resourceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let context = ExecutionContext(
                    spaceID: spaceID,
                    kind: .localFolder,
                    resourceID: resourceID,
                    hostReference: HostPrivateReference(rawValue: "resource-context:\(resourceID.description)")
                )
                _ = try await self.storage.transact { snapshot in
                    guard let resource = snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == spaceID }), resource.kind == .folder else {
                        throw HostProtocolError.unknownResource(resourceID)
                    }
                    guard !snapshot.executionContexts.contains(where: { $0.resourceID == resourceID && $0.kind == .localFolder }) else {
                        throw HostProtocolError.resourceInUse(resourceID)
                    }
                    snapshot.executionContexts.append(context)
                }
                return try TypedPayload(CreateLocalFolderContextResultPayload(contextID: context.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == AttachExecutionContextCommandPayload.identifier:
            let command = try AttachExecutionContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let sessionID = try Self.sessionID(from: command.sessionID)
            let contextID = try Self.executionContextID(from: command.contextID)
            guard let spaceID = try await storage.load().executionContexts.first(where: { $0.id == contextID })?.spaceID else {
                throw HostProtocolError.unknownExecutionContext(contextID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                _ = try await self.storage.transact { snapshot in
                    guard let context = snapshot.executionContexts.first(where: { $0.id == contextID }) else {
                        throw HostProtocolError.unknownExecutionContext(contextID)
                    }
                    guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else {
                        throw HostProtocolError.unknownSession(sessionID)
                    }
                    guard snapshot.sessions[index].spaceID == context.spaceID else {
                        throw HostProtocolError.invalidExecutionContext(contextID)
                    }
                    snapshot.sessions[index].executionContextID = contextID
                }
                return try TypedPayload(ExecutionContextMutationResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateRepositoryCheckoutContextCommandPayload.identifier:
            let command = try CreateRepositoryCheckoutContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            let resourceID = try Self.resourceID(from: command.resourceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let context = ExecutionContext(spaceID: spaceID, kind: .repositoryCheckout, resourceID: resourceID, hostReference: .init(rawValue: "repository-checkout:\(resourceID.description)"))
                _ = try await self.storage.transact { snapshot in
                    guard let resource = snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == spaceID }), resource.kind == .repository else { throw HostProtocolError.unknownResource(resourceID) }
                    guard !snapshot.executionContexts.contains(where: { $0.resourceID == resourceID && $0.kind == .repositoryCheckout }) else { throw HostProtocolError.resourceInUse(resourceID) }
                    snapshot.executionContexts.append(context)
                }
                return try TypedPayload(CreateRepositoryCheckoutContextResultPayload(contextID: context.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == RemoveExecutionContextCommandPayload.identifier:
            let command = try RemoveExecutionContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let contextID = try Self.executionContextID(from: command.contextID)
            if let replayed = try await durableReplayResult(for: envelope) {
                payload = replayed
            } else {
                guard let spaceID = try await storage.load().executionContexts.first(where: { $0.id == contextID })?.spaceID else {
                    throw HostProtocolError.unknownExecutionContext(contextID)
                }
                payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                    _ = try await self.storage.transact { snapshot in
                        guard snapshot.executionContexts.contains(where: { $0.id == contextID }) else {
                            throw HostProtocolError.unknownExecutionContext(contextID)
                        }
                        guard !snapshot.sessions.contains(where: { $0.executionContextID == contextID }) else {
                            throw HostProtocolError.executionContextInUse(contextID)
                        }
                        snapshot.executionContexts.removeAll(where: { $0.id == contextID })
                    }
                    return try TypedPayload(ExecutionContextMutationResultPayload())
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == DetachExecutionContextCommandPayload.identifier:
            let command = try DetachExecutionContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let sessionID = try Self.sessionID(from: command.sessionID)
            guard let spaceID = try await storage.load().sessions.first(where: { $0.id == sessionID })?.spaceID else {
                throw HostProtocolError.unknownSession(sessionID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                _ = try await self.storage.transact { snapshot in
                    guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else {
                        throw HostProtocolError.unknownSession(sessionID)
                    }
                    snapshot.sessions[index].executionContextID = nil
                }
                return try TypedPayload(ExecutionContextMutationResultPayload())
            }
            kind = .commandResult
        default:
            throw HostProtocolError.unsupportedRequest(kind: envelope.kind, payload: envelope.payload.identifier)
        }
        return ProtocolEnvelope(
            messageID: envelope.messageID,
            connectionID: envelope.connectionID,
            connectionSequence: envelope.connectionSequence,
            kind: kind,
            channel: .state,
            correlationID: envelope.correlationID,
            payload: payload
        )
    }

    private static func spaceID(from value: String) throws -> SpaceID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return SpaceID(rawValue: rawValue)
    }

    private func executeDurably(
        envelope: ProtocolEnvelope,
        spaceID: SpaceID,
        operation: () async throws -> TypedPayload
    ) async throws -> TypedPayload {
        if let replayed = try await durableReplayResult(for: envelope) {
            return replayed
        }
        guard let rawCommandID = UUID(uuidString: envelope.messageID) else {
            return try await operation()
        }
        let command = DurableCommand(
            id: CommandID(rawValue: rawCommandID),
            spaceID: spaceID,
            payloadDigest: Self.payloadDigest(envelope.payload)
        )
        switch try await storage.acceptCommand(command) {
        case .accepted:
            _ = try await storage.transitionCommand(id: command.id, to: .executing)
            do {
                let payload = try await operation()
                let result = DurableCommandResult(
                    payloadIdentifier: payload.identifier.rawValue,
                    schemaVersion: payload.schemaVersion,
                    protobufBytes: payload.protobufBytes
                )
                _ = try await storage.transitionCommand(id: command.id, to: .succeeded, result: result)
                return payload
            } catch {
                _ = try? await storage.transitionCommand(id: command.id, to: .failed)
                throw error
            }
        case .duplicate(let stored):
            guard stored.lifecycle == .succeeded, let result = stored.result else {
                throw HostProtocolError.commandIncomplete(command.id)
            }
            return TypedPayload(
                identifier: PayloadIdentifier(rawValue: result.payloadIdentifier),
                schemaVersion: result.schemaVersion,
                protobufBytes: result.protobufBytes,
                stateAffecting: true
            )
        case .conflict:
            throw HostProtocolError.commandIDConflict(command.id)
        }
    }

    private func durableReplayResult(for envelope: ProtocolEnvelope) async throws -> TypedPayload? {
        guard let rawCommandID = UUID(uuidString: envelope.messageID) else { return nil }
        let commandID = CommandID(rawValue: rawCommandID)
        guard let stored = try await storage.load().commands.first(where: { $0.id == commandID }) else { return nil }
        guard stored.payloadDigest == Self.payloadDigest(envelope.payload) else {
            throw HostProtocolError.commandIDConflict(commandID)
        }
        guard stored.lifecycle == .succeeded, let result = stored.result else {
            throw HostProtocolError.commandIncomplete(commandID)
        }
        return TypedPayload(
            identifier: PayloadIdentifier(rawValue: result.payloadIdentifier),
            schemaVersion: result.schemaVersion,
            protobufBytes: result.protobufBytes,
            stateAffecting: true
        )
    }

    private static func payloadDigest(_ payload: TypedPayload) -> String {
        let digest = SHA256.hash(data: payload.protobufBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sessionID(from value: String) throws -> SessionID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return SessionID(rawValue: rawValue)
    }

    private static func resourceID(from value: String) throws -> ResourceID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return ResourceID(rawValue: rawValue)
    }

    private static func executionContextID(from value: String) throws -> ExecutionContextID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return ExecutionContextID(rawValue: rawValue)
    }

    private static func localDirectory(from path: String) throws -> URL {
        guard path.hasPrefix("/") else { throw HostProtocolError.invalidResourcePath(path) }
        let directory = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HostProtocolError.invalidResourcePath(path)
        }
        return directory
    }

    private static func isGitRepository(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path)
    }

    private func executionContext(for sessionID: SessionID, in spaceID: SpaceID) async throws -> ExecutionContextID {
        let snapshot = try await storage.load()
        guard let session = snapshot.sessions.first(where: { $0.id == sessionID && $0.spaceID == spaceID }) else {
            throw HostProtocolError.unknownSession(sessionID)
        }
        if let executionContextID = session.executionContextID {
            if let context = snapshot.executionContexts.first(where: { $0.id == executionContextID }),
                context.kind == .managedTemporarySandbox || context.kind == .managedPersistentSandbox {
                try await managedSandboxes?.touch(context)
            }
            return executionContextID
        }
        guard let managedSandboxes else { throw HostProtocolError.runtimeUnavailable }
        do {
            return try await managedSandboxes.provision(for: sessionID, persistence: .temporary).id
        } catch ManagedSandboxService.Error.sessionAlreadyHasExecutionContext {
            guard let executionContextID = try await storage.load().sessions.first(where: { $0.id == sessionID })?.executionContextID else {
                throw HostProtocolError.unknownSession(sessionID)
            }
            return executionContextID
        }
    }
}

public enum HostProtocolError: Swift.Error, Sendable, Equatable {
    case unsupportedRequest(kind: WireMessageKind, payload: PayloadIdentifier)
    case invalidIdentity(String)
    case unknownSpace(SpaceID)
    case unknownSession(SessionID)
    case unknownRun(RunID)
    case unknownResource(ResourceID)
    case unknownExecutionContext(ExecutionContextID)
    case duplicateResource(ResourceID)
    case resourceInUse(ResourceID)
    case executionContextInUse(ExecutionContextID)
    case commandIDConflict(CommandID)
    case commandIncomplete(CommandID)
    case invalidResourcePath(String)
    case invalidExecutionContext(ExecutionContextID)
    case spaceNotEmpty(SpaceID)
    case runtimeUnavailable
}

extension LocalHost: RunEventEndpoint {}

/// Host-facing runtime contract. ACP, Process, and UI concerns remain in a macOS adapter.
public protocol RunRuntime: Sendable {
    func start(run: Run) async throws
    func cancel(runID: RunID) async throws
}

public protocol PromptRunRuntime: RunRuntime {
    func send(
        message: String,
        to runID: RunID,
        onAssistantTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String?
}

public actor RunCoordinator {
    public enum Error: Swift.Error, Sendable, Equatable {
        case duplicateRun(RunID)
        case unknownRun(RunID)
        case invalidTransition(from: RunLifecycle, to: RunLifecycle)
    }

    private let storage: StorageRepository
    private let runtime: any RunRuntime
    private let eventPublisher: RunEventPublisher?

    public init(
        storage: StorageRepository,
        runtime: any RunRuntime,
        eventPublisher: RunEventPublisher? = nil
    ) {
        self.storage = storage
        self.runtime = runtime
        self.eventPublisher = eventPublisher
    }

    public func start(_ run: Run) async throws {
        guard run.lifecycle == .queued else { throw Error.invalidTransition(from: run.lifecycle, to: .running) }
        _ = try await storage.transact { snapshot in
            guard !snapshot.runs.contains(where: { $0.id == run.id }) else { throw Error.duplicateRun(run.id) }
            snapshot.runs.append(run)
        }
        try await updateLifecycle(.preparingContext, for: run.id)
        do {
            try await runtime.start(run: run)
            try await updateLifecycle(.startingAgent, for: run.id)
            try await updateLifecycle(.running, for: run.id)
        } catch {
            try? await updateLifecycle(.failed, for: run.id)
            throw error
        }
    }

    /// Starts a Run that was atomically persisted with another Host-owned command.
    public func startPersisted(_ run: Run) async throws {
        guard try await self.run(for: run.id)?.lifecycle == .queued else { throw Error.invalidTransition(from: run.lifecycle, to: .running) }
        try await updateLifecycle(.preparingContext, for: run.id)
        do {
            try await runtime.start(run: run)
            try await updateLifecycle(.startingAgent, for: run.id)
            try await updateLifecycle(.running, for: run.id)
        } catch {
            try? await updateLifecycle(.failed, for: run.id)
            throw error
        }
    }

    public func complete(_ runID: RunID) async throws {
        try await updateLifecycle(.succeeded, for: runID)
    }

    public func cancel(_ runID: RunID) async throws {
        guard let run = try await run(for: runID) else { throw Error.unknownRun(runID) }
        guard run.lifecycle.canTransition(to: .cancelling) else {
            throw Error.invalidTransition(from: run.lifecycle, to: .cancelling)
        }
        try await updateLifecycle(.cancelling, for: runID)
        do {
            try await runtime.cancel(runID: runID)
            try await updateLifecycle(.cancelled, for: runID)
        } catch {
            try? await updateLifecycle(.failed, for: runID)
            throw error
        }
    }

    public func run(for id: RunID) async throws -> Run? {
        try await storage.load().runs.first(where: { $0.id == id })
    }

    private func updateLifecycle(_ lifecycle: RunLifecycle, for id: RunID) async throws {
        let snapshot = try await storage.transact { snapshot in
            guard let index = snapshot.runs.firstIndex(where: { $0.id == id }) else { throw Error.unknownRun(id) }
            let current = snapshot.runs[index].lifecycle
            guard current.canTransition(to: lifecycle) else {
                throw Error.invalidTransition(from: current, to: lifecycle)
            }
            snapshot.runs[index].lifecycle = lifecycle
        }
        guard let run = snapshot.runs.first(where: { $0.id == id }) else { throw Error.unknownRun(id) }
        await eventPublisher?.publish(for: run, kind: .lifecycle(lifecycle))
    }
}
