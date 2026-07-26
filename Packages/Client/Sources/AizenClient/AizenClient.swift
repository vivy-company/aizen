import AizenCore
import AizenTransport
import AizenWire
import Foundation

/// Client synchronisation and projections shared by Mac, Mobile, and CLI.
public enum AizenClientModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
}

public enum ClientConnectionState: Sendable, Hashable {
    case disconnected
    case connected(protocolGeneration: UInt32)
}

public struct SpaceProjection: Sendable, Hashable {
    public let activeSpaceID: SpaceID?
    public let spaces: [Space]

    public init(activeSpaceID: SpaceID? = nil, spaces: [Space] = []) {
        precondition(activeSpaceID == nil || spaces.contains(where: { $0.id == activeSpaceID }), "Active Space must belong to this projection")
        self.activeSpaceID = activeSpaceID
        self.spaces = spaces
    }

    public func selecting(_ spaceID: SpaceID) -> Self {
        precondition(spaces.contains(where: { $0.id == spaceID }), "Cannot select a Space outside the current projection")
        return Self(activeSpaceID: spaceID, spaces: spaces)
    }
}

public actor HostClient {
    public enum Error: Swift.Error, Sendable, Equatable {
        case sequenceExhausted
        case unexpectedPayload(PayloadIdentifier)
        case invalidIdentity(String)
        case eventStreamingUnavailable
    }

    private let transport: any WireTransport
    private let eventTransport: (any RunEventTransport)?
    private var nextSequence: UInt64 = 1
    public private(set) var connectionState: ClientConnectionState = .disconnected

    public init(transport: any WireTransport) {
        self.transport = transport
        eventTransport = transport as? any RunEventTransport
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let response = try await transport.send(envelope)
        connectionState = .connected(protocolGeneration: response.protocolGeneration)
        return response
    }

    public func disconnect() {
        connectionState = .disconnected
    }

    public func runEvents() async throws -> AsyncStream<RunEvent> {
        guard let eventTransport else { throw Error.eventStreamingUnavailable }
        return try await eventTransport.runEvents()
    }

    public func snapshot(scope: String = "host") async throws -> SnapshotResponsePayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(SnapshotRequestPayload(scope: scope))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == SnapshotResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try SnapshotResponsePayload(protobufBytes: response.payload.protobufBytes)
    }

    /// Returns the Storage-owned snapshot representation without exposing Wire payload types to UI clients.
    public func snapshotData(scope: String = "host") async throws -> Data {
        try await snapshot(scope: scope).snapshot
    }

    public func spaces() async throws -> [Space] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListSpacesQueryPayload())
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListSpacesResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListSpacesResponsePayload(protobufBytes: response.payload.protobufBytes).spaces
    }

    public func createSpace(name: String, icon: String? = nil, summary: String? = nil) async throws -> SpaceID {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(CreateSpaceCommandPayload(name: name, icon: icon, summary: summary))
        ))
        guard response.kind == .commandResult, response.payload.identifier == CreateSpaceResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        let result = try CreateSpaceResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let uuid = UUID(uuidString: result.spaceID) else { throw Error.invalidIdentity(result.spaceID) }
        return SpaceID(rawValue: uuid)
    }

    public func renameSpace(id: SpaceID, name: String) async throws {
        try await mutateSpace(RenameSpaceCommandPayload(spaceID: id.description, name: name))
    }

    public func deleteSpace(id: SpaceID) async throws {
        try await mutateSpace(DeleteSpaceCommandPayload(spaceID: id.description))
    }

    public func createConversation(spaceID: SpaceID, title: String) async throws -> SessionID {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(CreateConversationCommandPayload(spaceID: spaceID.description, title: title))
        ))
        guard response.kind == .commandResult, response.payload.identifier == CreateConversationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        let result = try CreateConversationResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let uuid = UUID(uuidString: result.sessionID) else { throw Error.invalidIdentity(result.sessionID) }
        return SessionID(rawValue: uuid)
    }

    public func conversations(spaceID: SpaceID? = nil) async throws -> [Session] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListConversationsQueryPayload(spaceID: spaceID?.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListConversationsResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListConversationsResponsePayload(protobufBytes: response.payload.protobufBytes).conversations
    }

    public func conversationTimeline(sessionID: SessionID) async throws -> [ConversationMessage] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(GetConversationTimelineQueryPayload(sessionID: sessionID.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == GetConversationTimelineResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try GetConversationTimelineResponsePayload(protobufBytes: response.payload.protobufBytes).messages
    }

    public func runs(spaceID: SpaceID? = nil) async throws -> [Run] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListRunsQueryPayload(spaceID: spaceID?.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListRunsResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListRunsResponsePayload(protobufBytes: response.payload.protobufBytes).runs
    }

    public func resources(spaceID: SpaceID? = nil) async throws -> [Resource] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListResourcesQueryPayload(spaceID: spaceID?.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListResourcesResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListResourcesResponsePayload(protobufBytes: response.payload.protobufBytes).resources
    }

    public func importLocalFolder(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(ImportLocalFolderCommandPayload(spaceID: spaceID.description, path: path, title: title))
        ))
        guard response.kind == .commandResult, response.payload.identifier == ImportLocalFolderResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        let result = try ImportLocalFolderResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let uuid = UUID(uuidString: result.resourceID) else { throw Error.invalidIdentity(result.resourceID) }
        return ResourceID(rawValue: uuid)
    }

    public func removeResource(id: ResourceID) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(RemoveResourceCommandPayload(resourceID: id.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == ResourceMutationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try ResourceMutationResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func executionContexts(spaceID: SpaceID? = nil, resourceID: ResourceID? = nil) async throws -> [ExecutionContext] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListExecutionContextsQueryPayload(spaceID: spaceID?.description, resourceID: resourceID?.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListExecutionContextsResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListExecutionContextsResponsePayload(protobufBytes: response.payload.protobufBytes).contexts
    }

    public func createLocalFolderContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(CreateLocalFolderContextCommandPayload(spaceID: spaceID.description, resourceID: resourceID.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == CreateLocalFolderContextResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        let result = try CreateLocalFolderContextResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let uuid = UUID(uuidString: result.contextID) else { throw Error.invalidIdentity(result.contextID) }
        return ExecutionContextID(rawValue: uuid)
    }

    public func attachExecutionContext(sessionID: SessionID, contextID: ExecutionContextID) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(AttachExecutionContextCommandPayload(sessionID: sessionID.description, contextID: contextID.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == ExecutionContextMutationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try ExecutionContextMutationResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func removeExecutionContext(id: ExecutionContextID) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(RemoveExecutionContextCommandPayload(contextID: id.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == ExecutionContextMutationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try ExecutionContextMutationResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func detachExecutionContext(sessionID: SessionID) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(DetachExecutionContextCommandPayload(sessionID: sessionID.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == ExecutionContextMutationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try ExecutionContextMutationResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func sendConversation(
        spaceID: SpaceID,
        sessionID: SessionID,
        content: String,
        messageID: ConversationMessageID = ConversationMessageID(),
        runID: RunID = RunID()
    ) async throws -> RunID {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(SendConversationCommandPayload(
                spaceID: spaceID.description,
                sessionID: sessionID.description,
                messageID: messageID.description,
                runID: runID.description,
                content: content
            ))
        ))
        guard response.kind == .commandResult, response.payload.identifier == SendConversationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        let result = try SendConversationResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let uuid = UUID(uuidString: result.runID) else { throw Error.invalidIdentity(result.runID) }
        return RunID(rawValue: uuid)
    }

    public func cancelRun(id: RunID) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(CancelRunCommandPayload(runID: id.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == CancelRunResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try CancelRunResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    private func nextConnectionSequence() throws -> UInt64 {
        guard nextSequence < UInt64.max else { throw Error.sequenceExhausted }
        defer { nextSequence += 1 }
        return nextSequence
    }

    private func mutateSpace(_ command: some WirePayload) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(command)
        ))
        guard response.kind == .commandResult, response.payload.identifier == SpaceMutationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try SpaceMutationResultPayload(protobufBytes: response.payload.protobufBytes)
    }
}
