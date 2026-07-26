import AizenCore
import AizenStorage
import AizenTransport
import AizenWire
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

    public init(
        storage: StorageRepository,
        conversationRuns: ConversationRunCoordinator? = nil,
        managedSandboxes: ManagedSandboxService? = nil
    ) {
        self.storage = storage
        self.conversationRuns = conversationRuns
        self.managedSandboxes = managedSandboxes
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
                CancelRunResultPayload.identifier
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
        case .command where envelope.payload.identifier == CreateSpaceCommandPayload.identifier:
            let command = try CreateSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let space = Space(name: command.name, icon: command.icon, summary: command.summary)
            _ = try await storage.transact { $0.spaces.append(space) }
            kind = .commandResult
            payload = try TypedPayload(CreateSpaceResultPayload(spaceID: space.id.description))
        case .command where envelope.payload.identifier == RenameSpaceCommandPayload.identifier:
            let command = try RenameSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            _ = try await storage.transact { snapshot in
                guard let index = snapshot.spaces.firstIndex(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                snapshot.spaces[index].name = command.name
            }
            kind = .commandResult
            payload = try TypedPayload(SpaceMutationResultPayload())
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
            let session = Session(spaceID: spaceID, kind: .conversation, title: command.title)
            _ = try await storage.transact { snapshot in
                guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                snapshot.sessions.append(session)
            }
            kind = .commandResult
            payload = try TypedPayload(CreateConversationResultPayload(sessionID: session.id.description))
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
            let executionContextID = try await executionContext(for: sessionID, in: spaceID)
            try await conversationRuns.submit(
                message: message,
                run: Run(id: runID, spaceID: spaceID, sessionID: sessionID, executionContextID: executionContextID)
            )
            kind = .commandResult
            payload = try TypedPayload(SendConversationResultPayload(runID: runID.description))
        case .command where envelope.payload.identifier == CancelRunCommandPayload.identifier:
            guard let conversationRuns else { throw HostProtocolError.runtimeUnavailable }
            let command = try CancelRunCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let rawRunID = UUID(uuidString: command.runID) else { throw HostProtocolError.invalidIdentity(command.runID) }
            try await conversationRuns.cancel(runID: RunID(rawValue: rawRunID))
            kind = .commandResult
            payload = try TypedPayload(CancelRunResultPayload())
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

    private static func sessionID(from value: String) throws -> SessionID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return SessionID(rawValue: rawValue)
    }

    private func executionContext(for sessionID: SessionID, in spaceID: SpaceID) async throws -> ExecutionContextID {
        let snapshot = try await storage.load()
        guard let session = snapshot.sessions.first(where: { $0.id == sessionID && $0.spaceID == spaceID }) else {
            throw HostProtocolError.unknownSession(sessionID)
        }
        if let executionContextID = session.executionContextID {
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
    case spaceNotEmpty(SpaceID)
    case runtimeUnavailable
}

/// Host-facing runtime contract. ACP, Process, and UI concerns remain in a macOS adapter.
public protocol RunRuntime: Sendable {
    func start(run: Run) async throws
    func cancel(runID: RunID) async throws
}

public protocol PromptRunRuntime: RunRuntime {
    func send(message: String, to runID: RunID) async throws -> String?
}

public actor RunCoordinator {
    public enum Error: Swift.Error, Sendable, Equatable {
        case duplicateRun(RunID)
        case unknownRun(RunID)
        case invalidTransition(from: RunLifecycle, to: RunLifecycle)
    }

    private let storage: StorageRepository
    private let runtime: any RunRuntime

    public init(storage: StorageRepository, runtime: any RunRuntime) {
        self.storage = storage
        self.runtime = runtime
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
        _ = try await storage.transact { snapshot in
            guard let index = snapshot.runs.firstIndex(where: { $0.id == id }) else { throw Error.unknownRun(id) }
            let current = snapshot.runs[index].lifecycle
            guard current.canTransition(to: lifecycle) else {
                throw Error.invalidTransition(from: current, to: lifecycle)
            }
            snapshot.runs[index].lifecycle = lifecycle
        }
    }
}
