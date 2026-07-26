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
    }

    private let transport: any WireTransport
    private var nextSequence: UInt64 = 1
    public private(set) var connectionState: ClientConnectionState = .disconnected

    public init(transport: any WireTransport) {
        self.transport = transport
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let response = try await transport.send(envelope)
        connectionState = .connected(protocolGeneration: response.protocolGeneration)
        return response
    }

    public func disconnect() {
        connectionState = .disconnected
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
