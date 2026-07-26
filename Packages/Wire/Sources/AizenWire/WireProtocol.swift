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

/// `snapshot` is a versioned Storage representation whose internal encoding is owned by Storage,
/// while this enclosing payload remains an actual protobuf message on every transport.
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
