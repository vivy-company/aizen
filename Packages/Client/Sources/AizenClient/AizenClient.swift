import AizenCore
import AizenTransport
import AizenWire
import Foundation

/// Client synchronisation and projections shared by Mac, Mobile, and CLI.
public enum AizenClientModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
    public static let productVersion = "2.0.0"
}

public enum ClientConnectionState: Sendable, Hashable {
    case disconnected
    case connecting
    case synchronizing
    case ready(protocolGeneration: UInt32)
    case reconnecting
    case blocked
    case failed
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

/// A Host consistency point used to recover Client feature projections after reconnecting.
public struct HostProjectionSnapshotResponse: Sendable, Hashable {
    public let cursor: UInt64
    public let snapshot: HostProjectionSnapshot

    public init(cursor: UInt64, snapshot: HostProjectionSnapshot) {
        self.cursor = cursor
        self.snapshot = snapshot
    }
}

// MARK: - Journal synchronization

public protocol JournalCursorStore: Sendable {
    func loadCursor() async throws -> UInt64
    func saveCursor(_ cursor: UInt64) async throws
}

/// Small durable cursor store owned by a Client, never by Host Storage.
public actor FileJournalCursorStore: JournalCursorStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func loadCursor() throws -> UInt64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UInt64.self, from: data)
    }

    public func saveCursor(_ cursor: UInt64) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cursor).write(to: url, options: .atomic)
    }
}

public enum JournalSynchronizationError: Swift.Error, Sendable, Equatable {
    case snapshotRequired
    case gap(expected: UInt64, received: UInt64)
}

public protocol CommandOutbox: Sendable {
    func enqueue(_ command: ProtocolEnvelope) async throws
    func pendingCommands() async throws -> [ProtocolEnvelope]
    func acknowledge(commandID: String) async throws
}

public enum CommandOutboxError: Swift.Error, Sendable, Equatable {
    case invalidCommand
}

/// Client-owned persistence for commands whose Host receipt may have been lost in transit.
public actor FileCommandOutbox: CommandOutbox {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func enqueue(_ command: ProtocolEnvelope) throws {
        guard command.kind == .command, UUID(uuidString: command.messageID) != nil else {
            throw CommandOutboxError.invalidCommand
        }
        var commands = try pendingCommands()
        guard !commands.contains(where: { $0.messageID == command.messageID }) else { return }
        commands.append(command)
        try save(commands)
    }

    public func pendingCommands() throws -> [ProtocolEnvelope] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ProtocolEnvelope].self, from: Data(contentsOf: url))
    }

    public func acknowledge(commandID: String) throws {
        let retained = try pendingCommands().filter { $0.messageID != commandID }
        try save(retained)
    }

    private func save(_ commands: [ProtocolEnvelope]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(commands).write(to: url, options: .atomic)
    }
}

/// Applies durable journal events serially. A reducer failure leaves the stored cursor unchanged.
public actor JournalEventSynchronizer {
    private let cursorStore: any JournalCursorStore
    private var cursor: UInt64?

    public init(cursorStore: any JournalCursorStore) {
        self.cursorStore = cursorStore
    }

    public func lastAppliedCursor() async throws -> UInt64 {
        if let cursor { return cursor }
        let stored = try await cursorStore.loadCursor()
        cursor = stored
        return stored
    }

    @discardableResult
    public func apply(
        _ response: ReadJournalEventsResponsePayload,
        reducer: @Sendable (JournalEvent) async throws -> Void
    ) async throws -> UInt64 {
        guard !response.snapshotRequired else { throw JournalSynchronizationError.snapshotRequired }
        var appliedCursor = try await lastAppliedCursor()
        for event in response.events {
            guard event.cursor > appliedCursor else { continue }
            let expected = appliedCursor + 1
            guard event.cursor == expected else {
                throw JournalSynchronizationError.gap(expected: expected, received: event.cursor)
            }
            try await reducer(event)
            try await cursorStore.saveCursor(event.cursor)
            appliedCursor = event.cursor
            cursor = appliedCursor
        }
        return appliedCursor
    }

    public func reset(to cursor: UInt64) async throws {
        try await cursorStore.saveCursor(cursor)
        self.cursor = cursor
    }
}

public actor HostClient {
    public enum Error: Swift.Error, Sendable, Equatable, LocalizedError {
        case sequenceExhausted
        case unexpectedPayload(PayloadIdentifier)
        case invalidIdentity(String)
        case eventStreamingUnavailable
        case hostFailure(code: String, message: String)
        case incompatibleHost(
            cliProductVersion: String,
            hostProductVersion: String,
            hostProtocolRange: ClosedRange<UInt32>,
            minimumCompatibleProductVersion: String
        )

        public var errorDescription: String? {
            switch self {
            case .sequenceExhausted:
                "The Client connection sequence is exhausted. Reconnect to Aizen Host."
            case .unexpectedPayload(let identifier):
                "Aizen Host returned an unexpected payload: \(identifier.rawValue)."
            case .invalidIdentity(let value):
                "Aizen Host returned an invalid identity: \(value)."
            case .eventStreamingUnavailable:
                "This Aizen Host connection does not support run event streaming."
            case let .hostFailure(code, message):
                "Aizen Host failed [\(code)]: \(message)"
            case let .incompatibleHost(cliProductVersion, hostProductVersion, hostProtocolRange, minimumCompatibleProductVersion):
                "Aizen CLI \(cliProductVersion) is incompatible with Host \(hostProductVersion). Host supports protocol generation \(hostProtocolRange.lowerBound)...\(hostProtocolRange.upperBound) and requires Client version \(minimumCompatibleProductVersion) or newer."
            }
        }
    }

    private let transport: any WireTransport
    private let eventTransport: (any RunEventTransport)?
    private let commandOutbox: (any CommandOutbox)?
    private var nextSequence: UInt64 = 1
    public private(set) var connectionState: ClientConnectionState = .disconnected

    public init(transport: any WireTransport, commandOutbox: (any CommandOutbox)? = nil) {
        self.transport = transport
        eventTransport = transport as? any RunEventTransport
        self.commandOutbox = commandOutbox
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        if envelope.kind == .command, UUID(uuidString: envelope.messageID) != nil {
            try await commandOutbox?.enqueue(envelope)
        }
        return try await transmit(envelope, acknowledgingCommand: true)
    }

    public func retryPendingCommands() async throws -> [ProtocolEnvelope] {
        guard let commandOutbox else { return [] }
        let pendingCommands = try await commandOutbox.pendingCommands()
        guard !pendingCommands.isEmpty else { return [] }
        connectionState = .synchronizing
        var responses: [ProtocolEnvelope] = []
        for command in pendingCommands {
            responses.append(try await transmit(command, acknowledgingCommand: true))
        }
        return responses
    }

    public func disconnect() {
        connectionState = .disconnected
    }

    public func negotiate() async throws -> CapabilitiesPayload {
        connectionState = connectionState == .disconnected ? .connecting : .reconnecting
        do {
            let response = try await transport.send(.init(
                messageID: UUID().uuidString,
                connectionSequence: try nextConnectionSequence(),
                kind: .hello,
                channel: .control,
                payload: try .init(HelloPayload(
                    minimumProtocolGeneration: UInt32(AizenClientModule.protocolGeneration),
                    maximumProtocolGeneration: UInt32(AizenClientModule.protocolGeneration),
                    productVersion: AizenClientModule.productVersion
                ))
            ))
            guard response.kind == .capabilities, response.payload.identifier == CapabilitiesPayload.identifier else {
                throw Error.unexpectedPayload(response.payload.identifier)
            }
            let capabilities = try CapabilitiesPayload(protobufBytes: response.payload.protobufBytes)
            guard capabilities.minimumProtocolGeneration <= AizenClientModule.protocolGeneration,
                  capabilities.maximumProtocolGeneration >= AizenClientModule.protocolGeneration,
                  Self.isCompatible(clientVersion: AizenClientModule.productVersion, hostMinimumVersion: capabilities.minimumCompatibleProductVersion) else {
                connectionState = .blocked
                throw Error.incompatibleHost(
                    cliProductVersion: AizenClientModule.productVersion,
                    hostProductVersion: capabilities.productVersion,
                    hostProtocolRange: capabilities.minimumProtocolGeneration...capabilities.maximumProtocolGeneration,
                    minimumCompatibleProductVersion: capabilities.minimumCompatibleProductVersion
                )
            }
            connectionState = .ready(protocolGeneration: response.protocolGeneration)
            return capabilities
        } catch {
            if connectionState != .blocked { connectionState = .failed }
            throw error
        }
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

    public func projectionSnapshot(scope: String = "host") async throws -> HostProjectionSnapshotResponse {
        let response = try await snapshot(scope: scope)
        return try .init(cursor: response.cursor, snapshot: JSONDecoder().decode(HostProjectionSnapshot.self, from: response.snapshot))
    }

    /// Reads client-safe runtime health from the Host; this never opens Host Storage in the Client.
    public func hostDiagnostics() async throws -> HostDiagnosticsSnapshot {
        let response = try await snapshot(scope: "diagnostics")
        return try JSONDecoder().decode(HostDiagnosticsSnapshot.self, from: response.snapshot)
    }

    /// Returns the Host projection bytes for compatibility with clients that own their decoding.
    public func snapshotData(scope: String = "host") async throws -> Data {
        try await snapshot(scope: scope).snapshot
    }

    public func journalEvents(after cursor: UInt64, spaceID: SpaceID? = nil) async throws -> ReadJournalEventsResponsePayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ReadJournalEventsQueryPayload(afterCursor: cursor, spaceID: spaceID?.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ReadJournalEventsResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ReadJournalEventsResponsePayload(protobufBytes: response.payload.protobufBytes)
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

    public func pendingPairingRequests() async throws -> [PendingPairingRequestRecordPayload] {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .query, channel: .control, payload: try .init(ListPendingPairingRequestsQueryPayload())))
        guard response.kind == .queryResponse, response.payload.identifier == ListPendingPairingRequestsResponsePayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try ListPendingPairingRequestsResponsePayload(protobufBytes: response.payload.protobufBytes).requests
    }

    public func approvePairingRequest(tokenID: UUID, capabilities: Set<String>) async throws {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .control, payload: try .init(ApprovePairingRequestCommandPayload(tokenID: tokenID, capabilities: capabilities))))
        guard response.kind == .commandResult, response.payload.identifier == PairingApprovalResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        _ = try PairingApprovalResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func rejectPairingRequest(tokenID: UUID) async throws {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .control, payload: try .init(RejectPairingRequestCommandPayload(tokenID: tokenID))))
        guard response.kind == .commandResult, response.payload.identifier == PairingApprovalResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        _ = try PairingApprovalResultPayload(protobufBytes: response.payload.protobufBytes)
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

    public func operations(spaceID: SpaceID? = nil, operationID: OperationID? = nil) async throws -> [AizenCore.Operation] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListOperationsQueryPayload(spaceID: spaceID?.description, operationID: operationID?.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListOperationsResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListOperationsResponsePayload(protobufBytes: response.payload.protobufBytes).operations
    }

    public func operationLog(
        operationID: OperationID,
        afterSequence: UInt64 = 0,
        maximumBytes: Int = ReadOperationLogQueryPayload.defaultMaximumBytes
    ) async throws -> ReadOperationLogResponsePayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ReadOperationLogQueryPayload(
                operationID: operationID.description,
                afterSequence: afterSequence,
                maximumBytes: maximumBytes
            ))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ReadOperationLogResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ReadOperationLogResponsePayload(protobufBytes: response.payload.protobufBytes)
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

    public func discoverXcodeProject(resourceID: ResourceID) async throws -> XcodeProjectDescriptor? {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(DiscoverXcodeProjectQueryPayload(resourceID: resourceID.description))
        ))
        guard response.kind == .queryResponse,
              response.payload.identifier == DiscoverXcodeProjectResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try DiscoverXcodeProjectResponsePayload(protobufBytes: response.payload.protobufBytes).project
    }

    public func openXcodeProject(resourceID: ResourceID, projectID: String) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(OpenXcodeProjectCommandPayload(resourceID: resourceID.description, projectID: projectID))
        ))
        guard response.kind == .commandResult,
              response.payload.identifier == OpenXcodeProjectResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try OpenXcodeProjectResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func buildXcodeProject(resourceID: ResourceID, projectID: String, scheme: String, destination: String = "platform=macOS") async throws -> OperationID {
        try await startXcodeProjectAction(resourceID: resourceID, projectID: projectID, scheme: scheme, destination: destination, action: .build)
    }

    public func testXcodeProject(resourceID: ResourceID, projectID: String, scheme: String, destination: String = "platform=macOS") async throws -> OperationID {
        try await startXcodeProjectAction(resourceID: resourceID, projectID: projectID, scheme: scheme, destination: destination, action: .test)
    }

    private func startXcodeProjectAction(
        resourceID: ResourceID,
        projectID: String,
        scheme: String,
        destination: String,
        action: XcodeProjectAction
    ) async throws -> OperationID {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(BuildXcodeProjectCommandPayload(resourceID: resourceID.description, projectID: projectID, scheme: scheme, destination: destination, action: action))))
        guard response.kind == .commandResult, response.payload.identifier == BuildXcodeProjectResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        let result = try BuildXcodeProjectResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let rawValue = UUID(uuidString: result.operationID) else { throw Error.invalidIdentity(result.operationID) }
        return OperationID(rawValue: rawValue)
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

    public func importLocalRepository(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(ImportLocalRepositoryCommandPayload(spaceID: spaceID.description, path: path, title: title))))
        guard response.kind == .commandResult, response.payload.identifier == ImportLocalRepositoryResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        let result = try ImportLocalRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let id = UUID(uuidString: result.resourceID) else { throw Error.invalidIdentity(result.resourceID) }
        return ResourceID(rawValue: id)
    }

    public func importWebResource(spaceID: SpaceID, url: URL, title: String? = nil) async throws -> ResourceID {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(ImportWebResourceCommandPayload(spaceID: spaceID.description, url: url, title: title))
        ))
        guard response.kind == .commandResult, response.payload.identifier == ImportWebResourceResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        let result = try ImportWebResourceResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let id = UUID(uuidString: result.resourceID) else { throw Error.invalidIdentity(result.resourceID) }
        return ResourceID(rawValue: id)
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

    public func refreshRepositoryResource(id: ResourceID) async throws -> RefreshRepositoryResourceResultPayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(RefreshRepositoryResourceCommandPayload(resourceID: id.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == RefreshRepositoryResourceResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try RefreshRepositoryResourceResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func repositoryStatus(id: ResourceID, maximumEntries: UInt32 = 200) async throws -> ReadRepositoryStatusResponsePayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ReadRepositoryStatusQueryPayload(resourceID: id.description, maximumEntries: maximumEntries))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ReadRepositoryStatusResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ReadRepositoryStatusResponsePayload(protobufBytes: response.payload.protobufBytes)
    }

    public func repositoryDiff(id: ResourceID, relativePath: String = "", maximumBytes: UInt32 = 262_144) async throws -> ReadRepositoryDiffResponsePayload {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .query, channel: .state, payload: try .init(ReadRepositoryDiffQueryPayload(resourceID: id.description, relativePath: relativePath, maximumBytes: maximumBytes))))
        guard response.kind == .queryResponse, response.payload.identifier == ReadRepositoryDiffResponsePayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try ReadRepositoryDiffResponsePayload(protobufBytes: response.payload.protobufBytes)
    }

    public func repositoryHistory(id: ResourceID, maximumCommits: UInt32 = 50) async throws -> ReadRepositoryHistoryResponsePayload {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .query, channel: .state, payload: try .init(ReadRepositoryHistoryQueryPayload(resourceID: id.description, maximumCommits: maximumCommits))))
        guard response.kind == .queryResponse, response.payload.identifier == ReadRepositoryHistoryResponsePayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try ReadRepositoryHistoryResponsePayload(protobufBytes: response.payload.protobufBytes)
    }

    public func repositoryBranches(id: ResourceID, maximumBranches: UInt32 = 50) async throws -> ReadRepositoryBranchesResponsePayload {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .query, channel: .state, payload: try .init(ReadRepositoryBranchesQueryPayload(resourceID: id.description, maximumBranches: maximumBranches))))
        guard response.kind == .queryResponse, response.payload.identifier == ReadRepositoryBranchesResponsePayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try ReadRepositoryBranchesResponsePayload(protobufBytes: response.payload.protobufBytes)
    }

    public func updateRepositoryIndex(id: ResourceID, relativePaths: [String], expectedIndexRevision: String, stage: Bool) async throws -> UpdateRepositoryIndexResultPayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(UpdateRepositoryIndexCommandPayload(
                resourceID: id.description,
                relativePaths: relativePaths,
                expectedIndexRevision: expectedIndexRevision,
                stage: stage
            ))
        ))
        guard response.kind == .commandResult, response.payload.identifier == UpdateRepositoryIndexResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try UpdateRepositoryIndexResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func commitRepository(id: ResourceID, message: String, expectedRepositoryRevision: String, expectedIndexRevision: String, amend: Bool = false) async throws -> CommitRepositoryResultPayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(CommitRepositoryCommandPayload(
                resourceID: id.description,
                message: message,
                expectedRepositoryRevision: expectedRepositoryRevision,
                expectedIndexRevision: expectedIndexRevision,
                amend: amend
            ))
        ))
        guard response.kind == .commandResult, response.payload.identifier == CommitRepositoryResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try CommitRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func updateRepositoryBranch(id: ResourceID, branchName: String, expectedRepositoryRevision: String, expectedIndexRevision: String, create: Bool) async throws -> UpdateRepositoryBranchResultPayload {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(UpdateRepositoryBranchCommandPayload(
                resourceID: id.description,
                branchName: branchName,
                expectedRepositoryRevision: expectedRepositoryRevision,
                expectedIndexRevision: expectedIndexRevision,
                create: create
            ))
        ))
        guard response.kind == .commandResult, response.payload.identifier == UpdateRepositoryBranchResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try UpdateRepositoryBranchResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func fetchRepository(id: ResourceID, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> FetchRepositoryResultPayload {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(FetchRepositoryCommandPayload(resourceID: id.description, expectedRepositoryRevision: expectedRepositoryRevision, expectedIndexRevision: expectedIndexRevision))))
        guard response.kind == .commandResult, response.payload.identifier == FetchRepositoryResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try FetchRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func pullRepository(id: ResourceID, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> PullRepositoryResultPayload {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(PullRepositoryCommandPayload(resourceID: id.description, expectedRepositoryRevision: expectedRepositoryRevision, expectedIndexRevision: expectedIndexRevision))))
        guard response.kind == .commandResult, response.payload.identifier == PullRepositoryResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try PullRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func pushRepository(id: ResourceID, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> PushRepositoryResultPayload {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(PushRepositoryCommandPayload(resourceID: id.description, expectedRepositoryRevision: expectedRepositoryRevision, expectedIndexRevision: expectedIndexRevision))))
        guard response.kind == .commandResult, response.payload.identifier == PushRepositoryResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try PushRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
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

    public func terminalSessions(spaceID: SpaceID? = nil) async throws -> [TerminalSession] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListTerminalSessionsQueryPayload(spaceID: spaceID?.description))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListTerminalSessionsResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListTerminalSessionsResponsePayload(protobufBytes: response.payload.protobufBytes).sessions
    }

    public func contextFiles(
        executionContextID: ExecutionContextID,
        relativePath: String = "",
        includeHidden: Bool = false
    ) async throws -> [ContextFileEntry] {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .query,
            channel: .state,
            payload: try .init(ListContextFilesQueryPayload(
                executionContextID: executionContextID.description,
                relativePath: relativePath,
                includeHidden: includeHidden
            ))
        ))
        guard response.kind == .queryResponse, response.payload.identifier == ListContextFilesResponsePayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try ListContextFilesResponsePayload(protobufBytes: response.payload.protobufBytes).entries
    }

    public func contextTextFile(executionContextID: ExecutionContextID, relativePath: String) async throws -> String {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .query, channel: .state, payload: try .init(ReadContextTextFileQueryPayload(executionContextID: executionContextID.description, relativePath: relativePath))))
        guard response.kind == .queryResponse, response.payload.identifier == ReadContextTextFileResponsePayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        return try ReadContextTextFileResponsePayload(protobufBytes: response.payload.protobufBytes).text
    }

    public func createTerminalSession(
        id: SessionID = SessionID(),
        spaceID: SpaceID,
        executionContextID: ExecutionContextID,
        title: String? = nil,
        initialCommand: String? = nil
    ) async throws -> TerminalSession {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .terminal,
            payload: try .init(CreateTerminalSessionCommandPayload(
                terminalSessionID: id.description,
                spaceID: spaceID.description,
                executionContextID: executionContextID.description,
                title: title,
                initialCommand: initialCommand
            ))
        ))
        guard response.kind == .commandResult, response.payload.identifier == CreateTerminalSessionResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        return try CreateTerminalSessionResultPayload(protobufBytes: response.payload.protobufBytes).session
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

    public func createRepositoryCheckoutContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(CreateRepositoryCheckoutContextCommandPayload(spaceID: spaceID.description, resourceID: resourceID.description))))
        guard response.kind == .commandResult, response.payload.identifier == CreateRepositoryCheckoutContextResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        let result = try CreateRepositoryCheckoutContextResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let id = UUID(uuidString: result.contextID) else { throw Error.invalidIdentity(result.contextID) }
        return ExecutionContextID(rawValue: id)
    }

    public func createLinkedWorktreeContext(spaceID: SpaceID, resourceID: ResourceID, destinationPath: String, branch: String, createBranch: Bool, baseBranch: String? = nil) async throws -> (contextID: ExecutionContextID, operationID: OperationID) {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(CreateLinkedWorktreeContextCommandPayload(spaceID: spaceID.description, resourceID: resourceID.description, destinationPath: destinationPath, branch: branch, createBranch: createBranch, baseBranch: baseBranch))))
        guard response.kind == .commandResult, response.payload.identifier == CreateLinkedWorktreeContextResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        let result = try CreateLinkedWorktreeContextResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let context = UUID(uuidString: result.contextID), let operation = UUID(uuidString: result.operationID) else { throw Error.invalidIdentity("Linked worktree result") }
        return (.init(rawValue: context), .init(rawValue: operation))
    }

    public func createIndependentContext(spaceID: SpaceID, resourceID: ResourceID, destinationPath: String, mode: IndependentContextMode) async throws -> (contextID: ExecutionContextID, operationID: OperationID) {
        let response = try await send(.init(messageID: UUID().uuidString, connectionSequence: try nextConnectionSequence(), kind: .command, channel: .state, payload: try .init(CreateIndependentContextCommandPayload(spaceID: spaceID.description, resourceID: resourceID.description, destinationPath: destinationPath, mode: mode))))
        guard response.kind == .commandResult, response.payload.identifier == CreateIndependentContextResultPayload.identifier else { throw Error.unexpectedPayload(response.payload.identifier) }
        let result = try CreateIndependentContextResultPayload(protobufBytes: response.payload.protobufBytes)
        guard let context = UUID(uuidString: result.contextID), let operation = UUID(uuidString: result.operationID) else { throw Error.invalidIdentity("Independent context result") }
        return (.init(rawValue: context), .init(rawValue: operation))
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

    public func cancelOperation(id: OperationID) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .state,
            payload: try .init(CancelOperationCommandPayload(operationID: id.description))
        ))
        guard response.kind == .commandResult, response.payload.identifier == CancelOperationResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try CancelOperationResultPayload(protobufBytes: response.payload.protobufBytes)
    }

    public func configureAgentLaunch(executablePath: String, arguments: [String], environment: [String: String]) async throws {
        let response = try await send(.init(
            messageID: UUID().uuidString,
            connectionSequence: try nextConnectionSequence(),
            kind: .command,
            channel: .control,
            payload: try .init(ConfigureAgentLaunchCommandPayload(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment
            ))
        ))
        guard response.kind == .commandResult, response.payload.identifier == ConfigureAgentLaunchResultPayload.identifier else {
            throw Error.unexpectedPayload(response.payload.identifier)
        }
        _ = try ConfigureAgentLaunchResultPayload(protobufBytes: response.payload.protobufBytes)
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

    private func transmit(_ envelope: ProtocolEnvelope, acknowledgingCommand: Bool) async throws -> ProtocolEnvelope {
        do {
            let response = try await transport.send(envelope)
            if response.kind == .error, response.payload.identifier == HostErrorPayload.identifier {
                let failure = try HostErrorPayload(protobufBytes: response.payload.protobufBytes)
                throw Error.hostFailure(code: failure.code, message: failure.message)
            }
            connectionState = .ready(protocolGeneration: response.protocolGeneration)
            if acknowledgingCommand, envelope.kind == .command, response.kind == .commandResult {
                try await commandOutbox?.acknowledge(commandID: envelope.messageID)
            }
            return response
        } catch {
            connectionState = .failed
            throw error
        }
    }

    private static func isCompatible(clientVersion: String, hostMinimumVersion: String) -> Bool {
        let client = clientVersion.split(separator: ".").compactMap { Int($0) }
        let minimum = hostMinimumVersion.split(separator: ".").compactMap { Int($0) }
        return client.starts(with: minimum)
    }
}
