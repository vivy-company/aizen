import AizenCore
import Foundation
import SwiftProtobuf

public struct PayloadIdentifier: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "Payload identifiers must not be empty")
        self.rawValue = rawValue
    }
}

public enum WireMessageKind: String, Codable, Sendable, Hashable {
    case hello
    case authentication
    case capabilities
    case command
    case commandReceipt
    case commandResult
    case query
    case queryResponse
    case snapshot
    case event
    case eventAcknowledgement
    case ping
    case pong
    case close
    case blob
    case error
}

public enum WireChannel: String, Codable, Sendable, Hashable {
    case control
    case state
    case runStream
    case terminal
    case blob
}

public struct WireAcknowledgement: Codable, Sendable, Hashable {
    public let sequence: UInt64
    public let messageID: String

    public init(sequence: UInt64, messageID: String) {
        self.sequence = sequence
        self.messageID = messageID
    }
}

public struct TypedPayload: Codable, Sendable, Hashable {
    public let identifier: PayloadIdentifier
    public let schemaVersion: UInt32
    public let protobufBytes: Data
    public let stateAffecting: Bool

    public init(identifier: PayloadIdentifier, schemaVersion: UInt32, protobufBytes: Data, stateAffecting: Bool) {
        precondition(schemaVersion > 0, "Payload schema versions start at one")
        self.identifier = identifier
        self.schemaVersion = schemaVersion
        self.protobufBytes = protobufBytes
        self.stateAffecting = stateAffecting
    }
}

public struct ProtocolEnvelope: Codable, Sendable, Hashable {
    public let protocolGeneration: UInt32
    public let messageID: String
    public let connectionID: String?
    public let connectionSequence: UInt64
    public let kind: WireMessageKind
    public let channel: WireChannel
    public let correlationID: String?
    public let acknowledgement: WireAcknowledgement?
    public let payload: TypedPayload

    public init(
        protocolGeneration: UInt32 = UInt32(AizenWireModule.protocolGeneration),
        messageID: String,
        connectionID: String? = nil,
        connectionSequence: UInt64,
        kind: WireMessageKind,
        channel: WireChannel,
        correlationID: String? = nil,
        acknowledgement: WireAcknowledgement? = nil,
        payload: TypedPayload
    ) {
        precondition(protocolGeneration > 0, "Protocol generations start at one")
        precondition(!messageID.isEmpty, "Envelopes require a message identifier")
        self.protocolGeneration = protocolGeneration
        self.messageID = messageID
        self.connectionID = connectionID
        self.connectionSequence = connectionSequence
        self.kind = kind
        self.channel = channel
        self.correlationID = correlationID
        self.acknowledgement = acknowledgement
        self.payload = payload
    }

    public func serializedData() throws -> Data {
        try protobuf.serializedData()
    }

    public init(serializedData: Data) throws {
        self = try Self(protobuf: AizenWireV1_ProtocolEnvelope(serializedBytes: serializedData))
    }

    public func debugJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public protocol WirePayload: Sendable {
    static var identifier: PayloadIdentifier { get }
    static var schemaVersion: UInt32 { get }
    static var stateAffecting: Bool { get }
    init(protobufBytes: Data) throws
    func protobufBytes() throws -> Data
}

public extension TypedPayload {
    init<P: WirePayload>(_ payload: P) throws {
        try self.init(
            identifier: P.identifier,
            schemaVersion: P.schemaVersion,
            protobufBytes: payload.protobufBytes(),
            stateAffecting: P.stateAffecting
        )
    }
}

public struct HelloPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.control.hello@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let minimumProtocolGeneration: UInt32
    public let maximumProtocolGeneration: UInt32
    public let productVersion: String

    public init(minimumProtocolGeneration: UInt32, maximumProtocolGeneration: UInt32, productVersion: String) {
        precondition(minimumProtocolGeneration > 0 && minimumProtocolGeneration <= maximumProtocolGeneration, "Protocol ranges must be ordered and non-zero")
        self.minimumProtocolGeneration = minimumProtocolGeneration
        self.maximumProtocolGeneration = maximumProtocolGeneration
        self.productVersion = productVersion
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_Hello(serializedBytes: protobufBytes)
        self.init(
            minimumProtocolGeneration: message.minimumProtocolGeneration,
            maximumProtocolGeneration: message.maximumProtocolGeneration,
            productVersion: message.productVersion
        )
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_Hello()
        message.minimumProtocolGeneration = minimumProtocolGeneration
        message.maximumProtocolGeneration = maximumProtocolGeneration
        message.productVersion = productVersion
        return try message.serializedData()
    }
}

public struct CapabilitiesPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.control.capabilities@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let identifiers: [PayloadIdentifier]

    public init(identifiers: [PayloadIdentifier]) {
        self.identifiers = identifiers.sorted { $0.rawValue < $1.rawValue }
    }

    public init(protobufBytes: Data) throws {
        self.init(identifiers: try AizenWireV1_Capabilities(serializedBytes: protobufBytes).identifiers.map { PayloadIdentifier(rawValue: $0) })
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_Capabilities()
        message.identifiers = identifiers.map(\.rawValue)
        return try message.serializedData()
    }
}

public struct SnapshotRequestPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.snapshot@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let scope: String
    public let afterCursor: UInt64

    public init(scope: String = "host", afterCursor: UInt64 = 0) {
        precondition(!scope.isEmpty, "Snapshot queries require a scope")
        self.scope = scope
        self.afterCursor = afterCursor
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_SnapshotRequest(serializedBytes: protobufBytes)
        self.init(scope: message.scope, afterCursor: message.afterCursor)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_SnapshotRequest()
        message.scope = scope
        message.afterCursor = afterCursor
        return try message.serializedData()
    }
}

public struct CreateSpaceCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.space.create@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let name: String
    public let icon: String?
    public let summary: String?

    public init(name: String, icon: String? = nil, summary: String? = nil) {
        precondition(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Spaces require a name")
        self.name = name
        self.icon = icon
        self.summary = summary
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_CreateSpaceCommand(serializedBytes: protobufBytes)
        self.init(name: message.name, icon: message.icon.isEmpty ? nil : message.icon, summary: message.summary.isEmpty ? nil : message.summary)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateSpaceCommand()
        message.name = name
        message.icon = icon ?? ""
        message.summary = summary ?? ""
        return try message.serializedData()
    }
}

public struct CreateSpaceResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.space.create@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let spaceID: String

    public init(spaceID: String) {
        precondition(!spaceID.isEmpty, "Created Spaces require an identity")
        self.spaceID = spaceID
    }

    public init(protobufBytes: Data) throws {
        self.init(spaceID: try AizenWireV1_CreateSpaceResult(serializedBytes: protobufBytes).spaceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateSpaceResult()
        message.spaceID = spaceID
        return try message.serializedData()
    }
}

public struct RenameSpaceCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.space.rename@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let spaceID: String
    public let name: String

    public init(spaceID: String, name: String) {
        precondition(!spaceID.isEmpty, "Spaces require an identity")
        precondition(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Spaces require a name")
        self.spaceID = spaceID
        self.name = name
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_RenameSpaceCommand(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID, name: message.name)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_RenameSpaceCommand()
        message.spaceID = spaceID
        message.name = name
        return try message.serializedData()
    }
}

public struct DeleteSpaceCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.space.delete@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let spaceID: String

    public init(spaceID: String) {
        precondition(!spaceID.isEmpty, "Spaces require an identity")
        self.spaceID = spaceID
    }

    public init(protobufBytes: Data) throws {
        self.init(spaceID: try AizenWireV1_DeleteSpaceCommand(serializedBytes: protobufBytes).spaceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_DeleteSpaceCommand()
        message.spaceID = spaceID
        return try message.serializedData()
    }
}

public struct SpaceMutationResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.space.mutation@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public init() {}
    public init(protobufBytes: Data) throws {
        _ = try AizenWireV1_SpaceMutationResult(serializedBytes: protobufBytes)
    }

    public func protobufBytes() throws -> Data {
        try AizenWireV1_SpaceMutationResult().serializedData()
    }
}

public struct CreateConversationCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.conversation.create@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let spaceID: String
    public let title: String

    public init(spaceID: String, title: String) {
        precondition(!spaceID.isEmpty, "Conversations require a Space identity")
        precondition(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Conversations require a title")
        self.spaceID = spaceID
        self.title = title
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_CreateConversationCommand(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID, title: message.title)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateConversationCommand()
        message.spaceID = spaceID
        message.title = title
        return try message.serializedData()
    }
}

public struct CreateConversationResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.conversation.create@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let sessionID: String

    public init(sessionID: String) {
        precondition(!sessionID.isEmpty, "Created Conversations require an identity")
        self.sessionID = sessionID
    }

    public init(protobufBytes: Data) throws {
        self.init(sessionID: try AizenWireV1_CreateConversationResult(serializedBytes: protobufBytes).sessionID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateConversationResult()
        message.sessionID = sessionID
        return try message.serializedData()
    }
}

/// `snapshot` is a versioned Storage representation whose internal encoding is owned by Storage,
/// while this enclosing payload remains an actual protobuf message on every transport.
public struct SendConversationCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.conversation.send@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let spaceID: String
    public let sessionID: String
    public let messageID: String
    public let runID: String
    public let content: String

    public init(spaceID: String, sessionID: String, messageID: String, runID: String, content: String) {
        precondition(!spaceID.isEmpty && !sessionID.isEmpty && !messageID.isEmpty && !runID.isEmpty, "Conversation sends require identities")
        precondition(!content.isEmpty, "Conversation sends require content")
        self.spaceID = spaceID
        self.sessionID = sessionID
        self.messageID = messageID
        self.runID = runID
        self.content = content
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_SendConversationCommand(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID, sessionID: message.sessionID, messageID: message.messageID, runID: message.runID, content: message.content)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_SendConversationCommand()
        message.spaceID = spaceID
        message.sessionID = sessionID
        message.messageID = messageID
        message.runID = runID
        message.content = content
        return try message.serializedData()
    }
}

public struct SendConversationResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.conversation.send@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let runID: String

    public init(runID: String) {
        precondition(!runID.isEmpty, "Conversation sends require a Run identity")
        self.runID = runID
    }

    public init(protobufBytes: Data) throws {
        self.init(runID: try AizenWireV1_SendConversationResult(serializedBytes: protobufBytes).runID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_SendConversationResult()
        message.runID = runID
        return try message.serializedData()
    }
}

public struct ListSpacesQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.space.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public init() {}

    public init(protobufBytes: Data) throws {
        _ = try AizenWireV1_ListSpacesQuery(serializedBytes: protobufBytes)
    }

    public func protobufBytes() throws -> Data {
        try AizenWireV1_ListSpacesQuery().serializedData()
    }
}

public struct ListSpacesResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.space.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let spaces: [Space]

    public init(spaces: [Space]) {
        self.spaces = spaces
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListSpacesResponse(serializedBytes: protobufBytes)
        spaces = try message.spaces.map { record in
            guard let uuid = UUID(uuidString: record.spaceID) else { throw WireCodecError.invalidIdentity(record.spaceID) }
            return Space(
                id: SpaceID(rawValue: uuid),
                name: record.name,
                icon: record.icon.isEmpty ? nil : record.icon,
                summary: record.summary.isEmpty ? nil : record.summary
            )
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListSpacesResponse()
        message.spaces = spaces.map { space in
            var record = AizenWireV1_SpaceRecord()
            record.spaceID = space.id.description
            record.name = space.name
            record.icon = space.icon ?? ""
            record.summary = space.summary ?? ""
            return record
        }
        return try message.serializedData()
    }
}

public struct SnapshotResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.snapshot.host@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let scope: String
    public let cursor: UInt64
    public let snapshot: Data

    public init(scope: String = "host", cursor: UInt64, snapshot: Data) {
        precondition(!scope.isEmpty, "Snapshots require a scope")
        self.scope = scope
        self.cursor = cursor
        self.snapshot = snapshot
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_SnapshotResponse(serializedBytes: protobufBytes)
        self.init(scope: message.scope, cursor: message.cursor, snapshot: message.snapshot)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_SnapshotResponse()
        message.scope = scope
        message.cursor = cursor
        message.snapshot = snapshot
        return try message.serializedData()
    }
}

public enum UnknownPayloadDisposition: Sendable, Hashable {
    case decoded
    case ignoredOptional
    case snapshotRequired
}

/// The registry is deliberately payload-centric: envelopes remain stable while features evolve independently.
public struct PayloadRegistry: Sendable, Hashable {
    private let identifiers: Set<PayloadIdentifier>

    public init(identifiers: Set<PayloadIdentifier>) {
        self.identifiers = identifiers
    }

    public func disposition(for payload: TypedPayload) -> UnknownPayloadDisposition {
        if identifiers.contains(payload.identifier) { return .decoded }
        return payload.stateAffecting ? .snapshotRequired : .ignoredOptional
    }
}

public enum WireErrorCode: String, Codable, Sendable, Hashable {
    case incompatibleProtocol
    case unsupportedPayload
    case commandIDConflict
    case snapshotRequired
    case malformedEnvelope
}

public enum WireRetryDirective: String, Codable, Sendable, Hashable {
    case never
    case reconnect
    case requestSnapshot
}

public enum WireCodecError: Error, Sendable, Equatable {
    case invalidProtocolGeneration(UInt32)
    case invalidMessageKind(Int)
    case invalidChannel(Int)
    case unsupportedPayloadEncoding(Int)
    case missingPayload
    case invalidIdentity(String)
}

private extension ProtocolEnvelope {
    var protobuf: AizenWireV1_ProtocolEnvelope {
        get throws {
            var value = AizenWireV1_ProtocolEnvelope()
            value.protocolGeneration = protocolGeneration
            value.messageID = messageID
            value.connectionID = connectionID ?? ""
            value.connectionSequence = connectionSequence
            value.kind = kind.protobuf
            value.channel = channel.protobuf
            value.correlationID = correlationID ?? ""
            if let acknowledgement {
                var protobufAcknowledgement = AizenWireV1_Acknowledgement()
                protobufAcknowledgement.sequence = acknowledgement.sequence
                protobufAcknowledgement.messageID = acknowledgement.messageID
                value.acknowledgement = protobufAcknowledgement
            }
            var protobufPayload = AizenWireV1_TypedPayload()
            protobufPayload.type = payload.identifier.rawValue
            protobufPayload.schemaVersion = payload.schemaVersion
            protobufPayload.encoding = .protobuf
            protobufPayload.bytes = payload.protobufBytes
            protobufPayload.stateAffecting = payload.stateAffecting
            value.payload = protobufPayload
            return value
        }
    }

    init(protobuf: AizenWireV1_ProtocolEnvelope) throws {
        guard protobuf.protocolGeneration > 0 else { throw WireCodecError.invalidProtocolGeneration(protobuf.protocolGeneration) }
        guard protobuf.hasPayload else { throw WireCodecError.missingPayload }
        guard let kind = WireMessageKind(protobuf: protobuf.kind) else { throw WireCodecError.invalidMessageKind(protobuf.kind.rawValue) }
        guard let channel = WireChannel(protobuf: protobuf.channel) else { throw WireCodecError.invalidChannel(protobuf.channel.rawValue) }
        guard protobuf.payload.encoding == .protobuf else { throw WireCodecError.unsupportedPayloadEncoding(protobuf.payload.encoding.rawValue) }

        self.init(
            protocolGeneration: protobuf.protocolGeneration,
            messageID: protobuf.messageID,
            connectionID: protobuf.connectionID.isEmpty ? nil : protobuf.connectionID,
            connectionSequence: protobuf.connectionSequence,
            kind: kind,
            channel: channel,
            correlationID: protobuf.correlationID.isEmpty ? nil : protobuf.correlationID,
            acknowledgement: protobuf.hasAcknowledgement ? .init(sequence: protobuf.acknowledgement.sequence, messageID: protobuf.acknowledgement.messageID) : nil,
            payload: .init(
                identifier: .init(rawValue: protobuf.payload.type),
                schemaVersion: protobuf.payload.schemaVersion,
                protobufBytes: protobuf.payload.bytes,
                stateAffecting: protobuf.payload.stateAffecting
            )
        )
    }
}

private extension WireMessageKind {
    var protobuf: AizenWireV1_MessageKind {
        switch self {
        case .hello: .hello
        case .authentication: .authentication
        case .capabilities: .capabilities
        case .command: .command
        case .commandReceipt: .commandReceipt
        case .commandResult: .commandResult
        case .query: .query
        case .queryResponse: .queryResponse
        case .snapshot: .snapshot
        case .event: .event
        case .eventAcknowledgement: .eventAcknowledgement
        case .ping: .ping
        case .pong: .pong
        case .close: .close
        case .blob: .blob
        case .error: .error
        }
    }

    init?(protobuf: AizenWireV1_MessageKind) {
        switch protobuf {
        case .hello: self = .hello
        case .authentication: self = .authentication
        case .capabilities: self = .capabilities
        case .command: self = .command
        case .commandReceipt: self = .commandReceipt
        case .commandResult: self = .commandResult
        case .query: self = .query
        case .queryResponse: self = .queryResponse
        case .snapshot: self = .snapshot
        case .event: self = .event
        case .eventAcknowledgement: self = .eventAcknowledgement
        case .ping: self = .ping
        case .pong: self = .pong
        case .close: self = .close
        case .blob: self = .blob
        case .error: self = .error
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

private extension WireChannel {
    var protobuf: AizenWireV1_LogicalChannel {
        switch self {
        case .control: .control
        case .state: .state
        case .runStream: .runStream
        case .terminal: .terminal
        case .blob: .blob
        }
    }

    init?(protobuf: AizenWireV1_LogicalChannel) {
        switch protobuf {
        case .control: self = .control
        case .state: self = .state
        case .runStream: self = .runStream
        case .terminal: self = .terminal
        case .blob: self = .blob
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}
