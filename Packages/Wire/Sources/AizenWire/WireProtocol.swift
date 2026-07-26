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

/// Stable failure categories exposed to Clients. The message is diagnostic; the code is automation-safe.
public enum HostErrorCode: String, Sendable, Hashable {
    case unsupportedRequest = "unsupported-request"
    case invalidRequest = "invalid-request"
    case unknownSpace = "unknown-space"
    case unknownSession = "unknown-session"
    case unknownRun = "unknown-run"
    case unknownResource = "unknown-resource"
    case unknownExecutionContext = "unknown-execution-context"
    case conflict = "conflict"
    case commandIncomplete = "command-incomplete"
    case unavailable = "unavailable"
    case commandFailed = "command-failed"
}

public struct HostErrorPayload: Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.error@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        precondition(!code.isEmpty && !message.isEmpty, "Host errors require a code and message")
        self.code = code
        self.message = message
    }

    public init(code: HostErrorCode, message: String) {
        self.init(code: code.rawValue, message: message)
    }

    public init(protobufBytes: Data) throws {
        let value = try AizenWireV1_HostError(serializedBytes: protobufBytes)
        self.init(code: value.code, message: value.message)
    }

    public func protobufBytes() throws -> Data {
        var value = AizenWireV1_HostError()
        value.code = code
        value.message = message
        return try value.serializedData()
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

extension HostErrorPayload: WirePayload {}

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
    public let minimumProtocolGeneration: UInt32
    public let maximumProtocolGeneration: UInt32
    public let productVersion: String
    public let minimumCompatibleProductVersion: String

    public init(
        identifiers: [PayloadIdentifier],
        minimumProtocolGeneration: UInt32 = UInt32(AizenWireModule.protocolGeneration),
        maximumProtocolGeneration: UInt32 = UInt32(AizenWireModule.protocolGeneration),
        productVersion: String = "2.0.0",
        minimumCompatibleProductVersion: String = "2.0.0"
    ) {
        precondition(minimumProtocolGeneration > 0 && minimumProtocolGeneration <= maximumProtocolGeneration, "Protocol ranges must be ordered and non-zero")
        self.identifiers = identifiers.sorted { $0.rawValue < $1.rawValue }
        self.minimumProtocolGeneration = minimumProtocolGeneration
        self.maximumProtocolGeneration = maximumProtocolGeneration
        self.productVersion = productVersion
        self.minimumCompatibleProductVersion = minimumCompatibleProductVersion
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_Capabilities(serializedBytes: protobufBytes)
        self.init(
            identifiers: message.identifiers.map { PayloadIdentifier(rawValue: $0) },
            minimumProtocolGeneration: message.minimumProtocolGeneration,
            maximumProtocolGeneration: message.maximumProtocolGeneration,
            productVersion: message.productVersion,
            minimumCompatibleProductVersion: message.minimumCompatibleProductVersion
        )
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_Capabilities()
        message.identifiers = identifiers.map(\.rawValue)
        message.minimumProtocolGeneration = minimumProtocolGeneration
        message.maximumProtocolGeneration = maximumProtocolGeneration
        message.productVersion = productVersion
        message.minimumCompatibleProductVersion = minimumCompatibleProductVersion
        return try message.serializedData()
    }
}

public struct AuthenticationStartPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.authentication.start@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let hostID: HostID
    public let deviceID: DeviceID
    public let connectionID: UUID
    public let clientNonce: Data
    public let deviceSigningPublicKey: Data
    public let deviceKeyAgreementPublicKey: Data
    public let clientEphemeralPublicKey: Data
    public let route: String

    public init(hostID: HostID, deviceID: DeviceID, connectionID: UUID, clientNonce: Data, deviceSigningPublicKey: Data, deviceKeyAgreementPublicKey: Data, clientEphemeralPublicKey: Data, route: String) {
        precondition(Self.isValid(clientNonce: clientNonce, signingKey: deviceSigningPublicKey, agreementKey: deviceKeyAgreementPublicKey, ephemeralKey: clientEphemeralPublicKey, route: route), "Authentication start has invalid cryptographic material")
        self.hostID = hostID
        self.deviceID = deviceID
        self.connectionID = connectionID
        self.clientNonce = clientNonce
        self.deviceSigningPublicKey = deviceSigningPublicKey
        self.deviceKeyAgreementPublicKey = deviceKeyAgreementPublicKey
        self.clientEphemeralPublicKey = clientEphemeralPublicKey
        self.route = route
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_AuthenticationStart(serializedBytes: protobufBytes)
        guard let hostID = UUID(uuidString: message.hostID), let deviceID = UUID(uuidString: message.deviceID), let connectionID = UUID(uuidString: message.connectionID),
              Self.isValid(clientNonce: message.clientNonce, signingKey: message.deviceSigningPublicKey, agreementKey: message.deviceKeyAgreementPublicKey, ephemeralKey: message.clientEphemeralPublicKey, route: message.route) else {
            throw WireCodecError.invalidAuthenticationPayload
        }
        self.init(hostID: .init(rawValue: hostID), deviceID: .init(rawValue: deviceID), connectionID: connectionID, clientNonce: message.clientNonce, deviceSigningPublicKey: message.deviceSigningPublicKey, deviceKeyAgreementPublicKey: message.deviceKeyAgreementPublicKey, clientEphemeralPublicKey: message.clientEphemeralPublicKey, route: message.route)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_AuthenticationStart()
        message.hostID = hostID.description
        message.deviceID = deviceID.description
        message.connectionID = connectionID.uuidString
        message.clientNonce = clientNonce
        message.deviceSigningPublicKey = deviceSigningPublicKey
        message.deviceKeyAgreementPublicKey = deviceKeyAgreementPublicKey
        message.clientEphemeralPublicKey = clientEphemeralPublicKey
        message.route = route
        return try message.serializedData()
    }

    private static func isValid(clientNonce: Data, signingKey: Data, agreementKey: Data, ephemeralKey: Data, route: String) -> Bool {
        clientNonce.count == 32 && signingKey.count == 32 && agreementKey.count == 32 && ephemeralKey.count == 32 && !route.isEmpty && route.utf8.count <= 32
    }
}

public struct AuthenticationChallengePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.authentication.challenge@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let hostID: HostID
    public let deviceID: DeviceID
    public let connectionID: UUID
    public let clientNonce: Data
    public let serverNonce: Data
    public let hostSigningPublicKey: Data
    public let hostKeyAgreementPublicKey: Data
    public let serverEphemeralPublicKey: Data
    public let route: String
    public let hostSignature: Data

    public init(hostID: HostID, deviceID: DeviceID, connectionID: UUID, clientNonce: Data, serverNonce: Data, hostSigningPublicKey: Data, hostKeyAgreementPublicKey: Data, serverEphemeralPublicKey: Data, route: String, hostSignature: Data) {
        precondition(Self.isValid(clientNonce: clientNonce, serverNonce: serverNonce, signingKey: hostSigningPublicKey, agreementKey: hostKeyAgreementPublicKey, ephemeralKey: serverEphemeralPublicKey, route: route, signature: hostSignature), "Authentication challenge has invalid cryptographic material")
        self.hostID = hostID
        self.deviceID = deviceID
        self.connectionID = connectionID
        self.clientNonce = clientNonce
        self.serverNonce = serverNonce
        self.hostSigningPublicKey = hostSigningPublicKey
        self.hostKeyAgreementPublicKey = hostKeyAgreementPublicKey
        self.serverEphemeralPublicKey = serverEphemeralPublicKey
        self.route = route
        self.hostSignature = hostSignature
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_AuthenticationChallenge(serializedBytes: protobufBytes)
        guard let hostID = UUID(uuidString: message.hostID), let deviceID = UUID(uuidString: message.deviceID), let connectionID = UUID(uuidString: message.connectionID),
              Self.isValid(clientNonce: message.clientNonce, serverNonce: message.serverNonce, signingKey: message.hostSigningPublicKey, agreementKey: message.hostKeyAgreementPublicKey, ephemeralKey: message.serverEphemeralPublicKey, route: message.route, signature: message.hostSignature) else {
            throw WireCodecError.invalidAuthenticationPayload
        }
        self.init(hostID: .init(rawValue: hostID), deviceID: .init(rawValue: deviceID), connectionID: connectionID, clientNonce: message.clientNonce, serverNonce: message.serverNonce, hostSigningPublicKey: message.hostSigningPublicKey, hostKeyAgreementPublicKey: message.hostKeyAgreementPublicKey, serverEphemeralPublicKey: message.serverEphemeralPublicKey, route: message.route, hostSignature: message.hostSignature)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_AuthenticationChallenge()
        message.hostID = hostID.description
        message.deviceID = deviceID.description
        message.connectionID = connectionID.uuidString
        message.clientNonce = clientNonce
        message.serverNonce = serverNonce
        message.hostSigningPublicKey = hostSigningPublicKey
        message.hostKeyAgreementPublicKey = hostKeyAgreementPublicKey
        message.serverEphemeralPublicKey = serverEphemeralPublicKey
        message.route = route
        message.hostSignature = hostSignature
        return try message.serializedData()
    }

    private static func isValid(clientNonce: Data, serverNonce: Data, signingKey: Data, agreementKey: Data, ephemeralKey: Data, route: String, signature: Data) -> Bool {
        clientNonce.count == 32 && serverNonce.count == 32 && signingKey.count == 32 && agreementKey.count == 32 && ephemeralKey.count == 32 && signature.count == 64 && !route.isEmpty && route.utf8.count <= 32
    }
}

public struct AuthenticationProofPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.authentication.proof@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let connectionID: UUID
    public let deviceSignature: Data

    public init(connectionID: UUID, deviceSignature: Data) {
        precondition(deviceSignature.count == 64, "Authentication proofs require an Ed25519 signature")
        self.connectionID = connectionID
        self.deviceSignature = deviceSignature
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_AuthenticationProof(serializedBytes: protobufBytes)
        guard let connectionID = UUID(uuidString: message.connectionID), message.deviceSignature.count == 64 else {
            throw WireCodecError.invalidAuthenticationPayload
        }
        self.init(connectionID: connectionID, deviceSignature: message.deviceSignature)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_AuthenticationProof()
        message.connectionID = connectionID.uuidString
        message.deviceSignature = deviceSignature
        return try message.serializedData()
    }
}

/// First-device pairing request. Receipt only means the Host has queued it for local approval.
public struct PairingRequestPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.pairing.request@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let tokenID: UUID
    public let pairingSecret: Data
    public let hostID: HostID
    public let deviceID: DeviceID
    public let deviceDisplayName: String
    public let devicePlatform: String
    public let deviceSigningPublicKey: Data
    public let deviceKeyAgreementPublicKey: Data
    public let route: String

    public init(tokenID: UUID, pairingSecret: Data, hostID: HostID, deviceID: DeviceID, deviceDisplayName: String, devicePlatform: String, deviceSigningPublicKey: Data, deviceKeyAgreementPublicKey: Data, route: String) {
        precondition(Self.isValid(pairingSecret: pairingSecret, displayName: deviceDisplayName, platform: devicePlatform, signingKey: deviceSigningPublicKey, agreementKey: deviceKeyAgreementPublicKey, route: route), "Pairing request has invalid identity material")
        self.tokenID = tokenID
        self.pairingSecret = pairingSecret
        self.hostID = hostID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.devicePlatform = devicePlatform
        self.deviceSigningPublicKey = deviceSigningPublicKey
        self.deviceKeyAgreementPublicKey = deviceKeyAgreementPublicKey
        self.route = route
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_PairingRequest(serializedBytes: protobufBytes)
        guard let tokenID = UUID(uuidString: message.tokenID), let hostID = UUID(uuidString: message.hostID), let deviceID = UUID(uuidString: message.deviceID), Self.isValid(pairingSecret: message.pairingSecret, displayName: message.deviceDisplayName, platform: message.devicePlatform, signingKey: message.deviceSigningPublicKey, agreementKey: message.deviceKeyAgreementPublicKey, route: message.route) else { throw WireCodecError.invalidAuthenticationPayload }
        self.init(tokenID: tokenID, pairingSecret: message.pairingSecret, hostID: .init(rawValue: hostID), deviceID: .init(rawValue: deviceID), deviceDisplayName: message.deviceDisplayName, devicePlatform: message.devicePlatform, deviceSigningPublicKey: message.deviceSigningPublicKey, deviceKeyAgreementPublicKey: message.deviceKeyAgreementPublicKey, route: message.route)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_PairingRequest()
        message.tokenID = tokenID.uuidString
        message.pairingSecret = pairingSecret
        message.hostID = hostID.description
        message.deviceID = deviceID.description
        message.deviceDisplayName = deviceDisplayName
        message.devicePlatform = devicePlatform
        message.deviceSigningPublicKey = deviceSigningPublicKey
        message.deviceKeyAgreementPublicKey = deviceKeyAgreementPublicKey
        message.route = route
        return try message.serializedData()
    }

    private static func isValid(pairingSecret: Data, displayName: String, platform: String, signingKey: Data, agreementKey: Data, route: String) -> Bool {
        pairingSecret.count >= 32 && !displayName.isEmpty && displayName.utf8.count <= 128 && !platform.isEmpty && platform.utf8.count <= 64 && signingKey.count == 32 && agreementKey.count == 32 && !route.isEmpty && route.utf8.count <= 32
    }
}

public struct PairingPendingPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.pairing.pending@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let tokenID: UUID

    public init(tokenID: UUID) { self.tokenID = tokenID }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_PairingPending(serializedBytes: protobufBytes)
        guard let tokenID = UUID(uuidString: message.tokenID) else { throw WireCodecError.invalidAuthenticationPayload }
        self.init(tokenID: tokenID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_PairingPending()
        message.tokenID = tokenID.uuidString
        return try message.serializedData()
    }
}

public struct PendingPairingRequestRecordPayload: Sendable, Hashable, Identifiable {
    public let tokenID: UUID
    public let deviceID: DeviceID
    public let deviceDisplayName: String
    public let devicePlatform: String
    public let fingerprint: String
    public let route: String
    public let receivedAt: Date
    public var id: UUID { tokenID }
    public init(tokenID: UUID, deviceID: DeviceID, deviceDisplayName: String, devicePlatform: String, fingerprint: String, route: String, receivedAt: Date) {
        self.tokenID = tokenID; self.deviceID = deviceID; self.deviceDisplayName = deviceDisplayName; self.devicePlatform = devicePlatform; self.fingerprint = fingerprint; self.route = route; self.receivedAt = receivedAt
    }
}

public struct ListPendingPairingRequestsQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.pairing-pending@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public init() {}
    public init(protobufBytes: Data) throws { _ = try AizenWireV1_ListPendingPairingRequestsQuery(serializedBytes: protobufBytes) }
    public func protobufBytes() throws -> Data { try AizenWireV1_ListPendingPairingRequestsQuery().serializedData() }
}

public struct ListPendingPairingRequestsResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.pairing-pending@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let requests: [PendingPairingRequestRecordPayload]
    public init(requests: [PendingPairingRequestRecordPayload]) { self.requests = requests }
    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListPendingPairingRequestsResponse(serializedBytes: protobufBytes)
        requests = try message.requests.map { record in
            guard let tokenID = UUID(uuidString: record.tokenID), let deviceID = UUID(uuidString: record.deviceID), !record.deviceDisplayName.isEmpty, !record.devicePlatform.isEmpty, !record.fingerprint.isEmpty, !record.route.isEmpty, record.receivedAtUnixMilliseconds > 0 else { throw WireCodecError.invalidAuthenticationPayload }
            return .init(tokenID: tokenID, deviceID: .init(rawValue: deviceID), deviceDisplayName: record.deviceDisplayName, devicePlatform: record.devicePlatform, fingerprint: record.fingerprint, route: record.route, receivedAt: Date(timeIntervalSince1970: TimeInterval(record.receivedAtUnixMilliseconds) / 1_000))
        }
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListPendingPairingRequestsResponse()
        message.requests = requests.map { request in
            var record = AizenWireV1_PendingPairingRequestRecord(); record.tokenID = request.tokenID.uuidString; record.deviceID = request.deviceID.description; record.deviceDisplayName = request.deviceDisplayName; record.devicePlatform = request.devicePlatform; record.fingerprint = request.fingerprint; record.route = request.route; record.receivedAtUnixMilliseconds = Int64((request.receivedAt.timeIntervalSince1970 * 1_000).rounded()); return record
        }
        return try message.serializedData()
    }
}

public struct ApprovePairingRequestCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.pairing.approve@1"); public static let schemaVersion: UInt32 = 1; public static let stateAffecting = true
    public let tokenID: UUID; public let capabilities: Set<String>
    public init(tokenID: UUID, capabilities: Set<String>) { self.tokenID = tokenID; self.capabilities = capabilities }
    public init(protobufBytes: Data) throws { let message = try AizenWireV1_ApprovePairingRequestCommand(serializedBytes: protobufBytes); guard let tokenID = UUID(uuidString: message.tokenID), !message.capabilities.isEmpty, message.capabilities.allSatisfy({ $0.utf8.count <= 64 }) else { throw WireCodecError.invalidAuthenticationPayload }; self.init(tokenID: tokenID, capabilities: Set(message.capabilities)) }
    public func protobufBytes() throws -> Data { var message = AizenWireV1_ApprovePairingRequestCommand(); message.tokenID = tokenID.uuidString; message.capabilities = capabilities.sorted(); return try message.serializedData() }
}

public struct RejectPairingRequestCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.pairing.reject@1"); public static let schemaVersion: UInt32 = 1; public static let stateAffecting = true
    public let tokenID: UUID; public init(tokenID: UUID) { self.tokenID = tokenID }
    public init(protobufBytes: Data) throws { let message = try AizenWireV1_RejectPairingRequestCommand(serializedBytes: protobufBytes); guard let tokenID = UUID(uuidString: message.tokenID) else { throw WireCodecError.invalidAuthenticationPayload }; self.init(tokenID: tokenID) }
    public func protobufBytes() throws -> Data { var message = AizenWireV1_RejectPairingRequestCommand(); message.tokenID = tokenID.uuidString; return try message.serializedData() }
}

public struct PairingApprovalResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.pairing-approval@1"); public static let schemaVersion: UInt32 = 1; public static let stateAffecting = true
    public let deviceID: DeviceID; public init(deviceID: DeviceID) { self.deviceID = deviceID }
    public init(protobufBytes: Data) throws { let message = try AizenWireV1_PairingApprovalResult(serializedBytes: protobufBytes); guard let id = UUID(uuidString: message.deviceID) else { throw WireCodecError.invalidAuthenticationPayload }; self.init(deviceID: .init(rawValue: id)) }
    public func protobufBytes() throws -> Data { var message = AizenWireV1_PairingApprovalResult(); message.deviceID = deviceID.description; return try message.serializedData() }
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

public struct CancelRunCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.run.cancel@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let runID: String

    public init(runID: String) {
        precondition(!runID.isEmpty, "Run cancellation requires a Run identity")
        self.runID = runID
    }

    public init(protobufBytes: Data) throws {
        self.init(runID: try AizenWireV1_CancelRunCommand(serializedBytes: protobufBytes).runID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CancelRunCommand()
        message.runID = runID
        return try message.serializedData()
    }
}

public struct CancelRunResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.run.cancel@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public init() {}

    public init(protobufBytes: Data) throws {
        _ = try AizenWireV1_CancelRunResult(serializedBytes: protobufBytes)
    }

    public func protobufBytes() throws -> Data {
        try AizenWireV1_CancelRunResult().serializedData()
    }
}

/// Sends the resolved ACP launch configuration over the authenticated local transport.
/// The Host owns persistence of the environment and never exposes it in snapshots.
public struct ConfigureAgentLaunchCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.agent.configure-launch@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(executablePath: String, arguments: [String], environment: [String: String]) {
        precondition(!executablePath.isEmpty, "Agent configuration requires an executable")
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ConfigureAgentLaunchCommand(serializedBytes: protobufBytes)
        self.init(executablePath: message.executablePath, arguments: message.arguments, environment: message.environment)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ConfigureAgentLaunchCommand()
        message.executablePath = executablePath
        message.arguments = arguments
        message.environment = environment
        return try message.serializedData()
    }
}

public struct ConfigureAgentLaunchResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.agent.configure-launch@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public init() {}

    public init(protobufBytes: Data) throws {
        _ = try AizenWireV1_ConfigureAgentLaunchResult(serializedBytes: protobufBytes)
    }

    public func protobufBytes() throws -> Data {
        try AizenWireV1_ConfigureAgentLaunchResult().serializedData()
    }
}

public struct RunEventPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.event.run@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let event: RunEvent

    public init(event: RunEvent) {
        self.event = event
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_RunEvent(serializedBytes: protobufBytes)
        guard let eventID = UUID(uuidString: message.eventID),
              let spaceID = UUID(uuidString: message.spaceID),
              let sessionID = UUID(uuidString: message.sessionID),
              let runID = UUID(uuidString: message.runID),
              message.sequence > 0 else {
            throw WireCodecError.invalidIdentity(message.eventID)
        }
        let kind: RunEventKind
        switch message.kind {
        case .lifecycle(let lifecycle):
            guard let value = RunLifecycle(rawValue: lifecycle) else { throw WireCodecError.invalidIdentity(lifecycle) }
            kind = .lifecycle(value)
        case .assistantTextDelta(let text):
            kind = .assistantTextDelta(text)
        case nil:
            throw WireCodecError.invalidIdentity(message.eventID)
        }
        event = RunEvent(
            id: eventID,
            sequence: message.sequence,
            spaceID: SpaceID(rawValue: spaceID),
            sessionID: SessionID(rawValue: sessionID),
            runID: RunID(rawValue: runID),
            kind: kind
        )
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_RunEvent()
        message.eventID = event.id.uuidString
        message.sequence = event.sequence
        message.spaceID = event.spaceID.description
        message.sessionID = event.sessionID.description
        message.runID = event.runID.description
        switch event.kind {
        case .lifecycle(let lifecycle): message.lifecycle = lifecycle.rawValue
        case .assistantTextDelta(let text): message.assistantTextDelta = text
        }
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

public struct ListConversationsQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.conversation.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let spaceID: String?

    public init(spaceID: String? = nil) { self.spaceID = spaceID }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListConversationsQuery(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID.isEmpty ? nil : message.spaceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListConversationsQuery()
        message.spaceID = spaceID ?? ""
        return try message.serializedData()
    }
}

public struct ListConversationsResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.conversation.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let conversations: [Session]

    public init(conversations: [Session]) { self.conversations = conversations }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListConversationsResponse(serializedBytes: protobufBytes)
        conversations = try message.conversations.map { record in
            guard let sessionUUID = UUID(uuidString: record.sessionID), let spaceUUID = UUID(uuidString: record.spaceID) else {
                throw WireCodecError.invalidIdentity(record.sessionID)
            }
            guard let lifecycle = SessionLifecycle(rawValue: record.lifecycle) else {
                throw WireCodecError.invalidLifecycle(record.lifecycle)
            }
            return Session(id: SessionID(rawValue: sessionUUID), spaceID: SpaceID(rawValue: spaceUUID), kind: .conversation, title: record.title, lifecycle: lifecycle)
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListConversationsResponse()
        message.conversations = conversations.map { conversation in
            var record = AizenWireV1_ConversationRecord()
            record.sessionID = conversation.id.description
            record.spaceID = conversation.spaceID.description
            record.title = conversation.title
            record.lifecycle = conversation.lifecycle.rawValue
            return record
        }
        return try message.serializedData()
    }
}

public struct GetConversationTimelineQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.conversation.timeline@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let sessionID: String

    public init(sessionID: String) {
        precondition(!sessionID.isEmpty, "Conversation timeline queries require a Session identity")
        self.sessionID = sessionID
    }

    public init(protobufBytes: Data) throws {
        self.init(sessionID: try AizenWireV1_GetConversationTimelineQuery(serializedBytes: protobufBytes).sessionID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_GetConversationTimelineQuery()
        message.sessionID = sessionID
        return try message.serializedData()
    }
}

public struct GetConversationTimelineResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.conversation.timeline@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let messages: [ConversationMessage]

    public init(messages: [ConversationMessage]) { self.messages = messages }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_GetConversationTimelineResponse(serializedBytes: protobufBytes)
        messages = try message.messages.map { record in
            guard let messageUUID = UUID(uuidString: record.messageID),
                let spaceUUID = UUID(uuidString: record.spaceID),
                let sessionUUID = UUID(uuidString: record.sessionID),
                let role = ConversationMessageRole(rawValue: record.role) else {
                throw WireCodecError.invalidIdentity(record.messageID)
            }
            let runID = record.runID.isEmpty ? nil : UUID(uuidString: record.runID).map(RunID.init(rawValue:))
            guard record.runID.isEmpty || runID != nil else { throw WireCodecError.invalidIdentity(record.runID) }
            return ConversationMessage(
                id: ConversationMessageID(rawValue: messageUUID),
                spaceID: SpaceID(rawValue: spaceUUID),
                sessionID: SessionID(rawValue: sessionUUID),
                runID: runID,
                role: role,
                content: record.content,
                createdAt: Date(timeIntervalSince1970: Double(record.createdAtMillis) / 1_000)
            )
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_GetConversationTimelineResponse()
        message.messages = messages.map { value in
            var record = AizenWireV1_ConversationMessageRecord()
            record.messageID = value.id.description
            record.spaceID = value.spaceID.description
            record.sessionID = value.sessionID.description
            record.runID = value.runID?.description ?? ""
            record.role = value.role.rawValue
            record.content = value.content
            record.createdAtMillis = Int64((value.createdAt.timeIntervalSince1970 * 1_000).rounded(.towardZero))
            return record
        }
        return try message.serializedData()
    }
}

public struct ListRunsQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.run.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let spaceID: String?

    public init(spaceID: String? = nil) { self.spaceID = spaceID }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListRunsQuery(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID.isEmpty ? nil : message.spaceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListRunsQuery()
        message.spaceID = spaceID ?? ""
        return try message.serializedData()
    }
}

public struct ListRunsResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.run.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let runs: [Run]

    public init(runs: [Run]) { self.runs = runs }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListRunsResponse(serializedBytes: protobufBytes)
        runs = try message.runs.map { record in
            guard let runUUID = UUID(uuidString: record.runID),
                let spaceUUID = UUID(uuidString: record.spaceID),
                let sessionUUID = UUID(uuidString: record.sessionID),
                let lifecycle = RunLifecycle(rawValue: record.lifecycle) else {
                throw WireCodecError.invalidIdentity(record.runID)
            }
            let executionContextID = record.executionContextID.isEmpty
                ? nil
                : UUID(uuidString: record.executionContextID).map(ExecutionContextID.init(rawValue:))
            guard record.executionContextID.isEmpty || executionContextID != nil else {
                throw WireCodecError.invalidIdentity(record.executionContextID)
            }
            return Run(
                id: RunID(rawValue: runUUID),
                spaceID: SpaceID(rawValue: spaceUUID),
                sessionID: SessionID(rawValue: sessionUUID),
                executionContextID: executionContextID,
                lifecycle: lifecycle
            )
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListRunsResponse()
        message.runs = runs.map { run in
            var record = AizenWireV1_RunRecord()
            record.runID = run.id.description
            record.spaceID = run.spaceID.description
            record.sessionID = run.sessionID.description
            record.executionContextID = run.executionContextID?.description ?? ""
            record.lifecycle = run.lifecycle.rawValue
            return record
        }
        return try message.serializedData()
    }
}

public struct ListOperationsQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.operation.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let spaceID: String?
    public let operationID: String?

    public init(spaceID: String? = nil, operationID: String? = nil) {
        self.spaceID = spaceID
        self.operationID = operationID
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListOperationsQuery(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID.isEmpty ? nil : message.spaceID, operationID: message.operationID.isEmpty ? nil : message.operationID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListOperationsQuery()
        message.spaceID = spaceID ?? ""
        message.operationID = operationID ?? ""
        return try message.serializedData()
    }
}

public struct ListOperationsResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.operation.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let operations: [AizenCore.Operation]

    public init(operations: [AizenCore.Operation]) { self.operations = operations }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListOperationsResponse(serializedBytes: protobufBytes)
        operations = try message.operations.map { record in
            guard let operationUUID = UUID(uuidString: record.operationID),
                  let spaceUUID = UUID(uuidString: record.spaceID),
                  let lifecycle = OperationLifecycle(rawValue: record.lifecycle) else {
                throw WireCodecError.invalidIdentity(record.operationID)
            }
            let sessionID = record.sessionID.isEmpty ? nil : UUID(uuidString: record.sessionID).map(SessionID.init(rawValue:))
            guard record.sessionID.isEmpty || sessionID != nil,
                  !record.hasProgress_p || (0...1).contains(record.progress) else {
                throw WireCodecError.invalidIdentity(record.operationID)
            }
            let failureDescription = record.failureDescription.isEmpty ? nil : record.failureDescription
            return AizenCore.Operation(id: .init(rawValue: operationUUID), spaceID: .init(rawValue: spaceUUID), sessionID: sessionID, lifecycle: lifecycle, progress: record.hasProgress_p ? record.progress : nil, failureDescription: failureDescription)
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListOperationsResponse()
        message.operations = operations.map { operation in
            var record = AizenWireV1_OperationRecord()
            record.operationID = operation.id.description
            record.spaceID = operation.spaceID.description
            record.sessionID = operation.sessionID?.description ?? ""
            record.lifecycle = operation.lifecycle.rawValue
            if let progress = operation.progress { record.progress = progress; record.hasProgress_p = true }
            record.failureDescription = operation.failureDescription ?? ""
            return record
        }
        return try message.serializedData()
    }
}

public struct ListResourcesQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.resource.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let spaceID: String?

    public init(spaceID: String? = nil) { self.spaceID = spaceID }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListResourcesQuery(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID.isEmpty ? nil : message.spaceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListResourcesQuery()
        message.spaceID = spaceID ?? ""
        return try message.serializedData()
    }
}

public struct ListResourcesResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.resource.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resources: [Resource]

    public init(resources: [Resource]) { self.resources = resources }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListResourcesResponse(serializedBytes: protobufBytes)
        resources = try message.resources.map { record in
            guard let resourceUUID = UUID(uuidString: record.resourceID), let spaceUUID = UUID(uuidString: record.spaceID) else {
                throw WireCodecError.invalidIdentity(record.resourceID)
            }
            let details = record.detailsJson.isEmpty
                ? ResourceDetails.none
                : try JSONDecoder().decode(ResourceDetails.self, from: record.detailsJson)
            return Resource(
                id: ResourceID(rawValue: resourceUUID),
                spaceID: SpaceID(rawValue: spaceUUID),
                kind: ResourceKind(rawValue: record.kind),
                title: record.title,
                details: details
            )
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListResourcesResponse()
        message.resources = try resources.map { resource in
            var record = AizenWireV1_ResourceRecord()
            record.resourceID = resource.id.description
            record.spaceID = resource.spaceID.description
            record.kind = resource.kind.rawValue
            record.title = resource.title
            record.detailsJson = try JSONEncoder().encode(resource.details)
            return record
        }
        return try message.serializedData()
    }
}

public struct DiscoverXcodeProjectQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.xcode-project.discover@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let resourceID: String

    public init(resourceID: String) { self.resourceID = resourceID }
    public init(protobufBytes: Data) throws {
        self.init(resourceID: try AizenWireV1_DiscoverXcodeProjectQuery(serializedBytes: protobufBytes).resourceID)
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_DiscoverXcodeProjectQuery()
        message.resourceID = resourceID
        return try message.serializedData()
    }
}

public struct DiscoverXcodeProjectResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.xcode-project.discover@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let project: XcodeProjectDescriptor?

    public init(project: XcodeProjectDescriptor?) { self.project = project }
    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_DiscoverXcodeProjectResponse(serializedBytes: protobufBytes)
        guard message.hasProject else { self.init(project: nil); return }
        let record = message.project
        guard let resourceUUID = UUID(uuidString: record.resourceID),
              let kind = XcodeProjectDescriptor.Kind(rawValue: record.kind) else {
            throw WireCodecError.invalidIdentity(record.resourceID)
        }
        self.init(project: .init(resourceID: ResourceID(rawValue: resourceUUID), id: record.id, name: record.name, kind: kind, schemes: record.schemes))
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_DiscoverXcodeProjectResponse()
        if let project {
            var record = AizenWireV1_XcodeProjectDescriptorRecord()
            record.resourceID = project.resourceID.description
            record.id = project.id
            record.name = project.name
            record.kind = project.kind.rawValue
            record.schemes = project.schemes
            message.project = record
        }
        return try message.serializedData()
    }
}

public struct OpenXcodeProjectCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.xcode-project.open@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String
    public let projectID: String

    public init(resourceID: String, projectID: String) {
        precondition(!resourceID.isEmpty && !projectID.isEmpty, "Opening an Xcode project requires a resource and project")
        self.resourceID = resourceID
        self.projectID = projectID
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_OpenXcodeProjectCommand(serializedBytes: protobufBytes)
        self.init(resourceID: message.resourceID, projectID: message.projectID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_OpenXcodeProjectCommand()
        message.resourceID = resourceID
        message.projectID = projectID
        return try message.serializedData()
    }
}

public struct OpenXcodeProjectResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.xcode-project.open@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public init() {}
    public init(protobufBytes: Data) throws { _ = try AizenWireV1_OpenXcodeProjectResult(serializedBytes: protobufBytes) }
    public func protobufBytes() throws -> Data { try AizenWireV1_OpenXcodeProjectResult().serializedData() }
}

public struct BuildXcodeProjectCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.xcode-project.build@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String; public let projectID: String; public let scheme: String; public let destination: String
    public init(resourceID: String, projectID: String, scheme: String, destination: String) {
        precondition(!resourceID.isEmpty && !projectID.isEmpty && !scheme.isEmpty && !destination.isEmpty, "Xcode builds require a resource, project, scheme, and destination")
        self.resourceID = resourceID; self.projectID = projectID; self.scheme = scheme; self.destination = destination
    }
    public init(protobufBytes: Data) throws { let value = try AizenWireV1_BuildXcodeProjectCommand(serializedBytes: protobufBytes); self.init(resourceID: value.resourceID, projectID: value.projectID, scheme: value.scheme, destination: value.destination) }
    public func protobufBytes() throws -> Data { var value = AizenWireV1_BuildXcodeProjectCommand(); value.resourceID = resourceID; value.projectID = projectID; value.scheme = scheme; value.destination = destination; return try value.serializedData() }
}

public struct BuildXcodeProjectResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.xcode-project.build@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let operationID: String
    public init(operationID: String) { self.operationID = operationID }
    public init(protobufBytes: Data) throws { self.init(operationID: try AizenWireV1_BuildXcodeProjectResult(serializedBytes: protobufBytes).operationID) }
    public func protobufBytes() throws -> Data { var value = AizenWireV1_BuildXcodeProjectResult(); value.operationID = operationID; return try value.serializedData() }
}

public struct ImportLocalFolderCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.resource.import-local-folder@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let spaceID: String
    public let path: String
    public let title: String?

    public init(spaceID: String, path: String, title: String? = nil) {
        precondition(!spaceID.isEmpty && !path.isEmpty, "Folder imports require a Space and path")
        self.spaceID = spaceID
        self.path = path
        self.title = title
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ImportLocalFolderCommand(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID, path: message.path, title: message.title.isEmpty ? nil : message.title)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ImportLocalFolderCommand()
        message.spaceID = spaceID
        message.path = path
        message.title = title ?? ""
        return try message.serializedData()
    }
}

public struct ImportLocalRepositoryCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.resource.import-local-repository@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let spaceID: String; public let path: String; public let title: String?
    public init(spaceID: String, path: String, title: String? = nil) { self.spaceID = spaceID; self.path = path; self.title = title }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_ImportLocalRepositoryCommand(serializedBytes: protobufBytes); self.init(spaceID: m.spaceID, path: m.path, title: m.hasTitle ? m.title : nil) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_ImportLocalRepositoryCommand(); m.spaceID = spaceID; m.path = path; if let title { m.title = title }; return try m.serializedData() }
}

public struct ImportLocalRepositoryResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.resource.import-local-repository@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String
    public init(resourceID: String) { self.resourceID = resourceID }
    public init(protobufBytes: Data) throws { self.init(resourceID: try AizenWireV1_ImportLocalRepositoryResult(serializedBytes: protobufBytes).resourceID) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_ImportLocalRepositoryResult(); m.resourceID = resourceID; return try m.serializedData() }
}

public struct ImportLocalFolderResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.resource.import-local-folder@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String

    public init(resourceID: String) { self.resourceID = resourceID }
    public init(protobufBytes: Data) throws { self.init(resourceID: try AizenWireV1_ImportLocalFolderResult(serializedBytes: protobufBytes).resourceID) }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ImportLocalFolderResult()
        message.resourceID = resourceID
        return try message.serializedData()
    }
}

public struct ImportWebResourceCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.resource.import-web@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let spaceID: String
    public let url: URL
    public let title: String?

    public init(spaceID: String, url: URL, title: String? = nil) {
        precondition(!spaceID.isEmpty, "Web imports require a Space")
        precondition(url.scheme != nil && url.host != nil, "Web imports require an absolute URL")
        self.spaceID = spaceID
        self.url = url
        self.title = title
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ImportWebResourceCommand(serializedBytes: protobufBytes)
        guard let url = URL(string: message.url), url.scheme != nil, url.host != nil else {
            throw WireCodecError.invalidURL(message.url)
        }
        self.init(spaceID: message.spaceID, url: url, title: message.hasTitle ? message.title : nil)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ImportWebResourceCommand()
        message.spaceID = spaceID
        message.url = url.absoluteString
        if let title { message.title = title }
        return try message.serializedData()
    }
}

public struct ImportWebResourceResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.resource.import-web@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String

    public init(resourceID: String) { self.resourceID = resourceID }

    public init(protobufBytes: Data) throws {
        self.init(resourceID: try AizenWireV1_ImportWebResourceResult(serializedBytes: protobufBytes).resourceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ImportWebResourceResult()
        message.resourceID = resourceID
        return try message.serializedData()
    }
}

public struct RemoveResourceCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.resource.remove@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String

    public init(resourceID: String) {
        precondition(!resourceID.isEmpty, "Resource removal requires an identity")
        self.resourceID = resourceID
    }

    public init(protobufBytes: Data) throws { self.init(resourceID: try AizenWireV1_RemoveResourceCommand(serializedBytes: protobufBytes).resourceID) }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_RemoveResourceCommand()
        message.resourceID = resourceID
        return try message.serializedData()
    }
}

public struct ResourceMutationResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.resource.mutation@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public init() {}
    public init(protobufBytes: Data) throws { _ = try AizenWireV1_ResourceMutationResult(serializedBytes: protobufBytes) }
    public func protobufBytes() throws -> Data { try AizenWireV1_ResourceMutationResult().serializedData() }
}

public struct RefreshRepositoryResourceCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.resource.refresh-repository@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String
    public init(resourceID: String) { self.resourceID = resourceID }
    public init(protobufBytes: Data) throws {
        self.init(resourceID: try AizenWireV1_RefreshRepositoryResourceCommand(serializedBytes: protobufBytes).resourceID)
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_RefreshRepositoryResourceCommand()
        message.resourceID = resourceID
        return try message.serializedData()
    }
}

public enum RepositoryResourceAvailability: String, Sendable, Hashable {
    case available
    case missing
    case notRepository
}

/// Safe, derived repository state returned by the Host. It intentionally contains no filesystem path.
public struct RefreshRepositoryResourceResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.resource.refresh-repository@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let resourceID: String
    public let availability: RepositoryResourceAvailability
    public let branch: String?
    public let isDetached: Bool
    public let hasSubmodules: Bool
    public let isRebaseInProgress: Bool

    public init(
        resourceID: String,
        availability: RepositoryResourceAvailability,
        branch: String? = nil,
        isDetached: Bool = false,
        hasSubmodules: Bool = false,
        isRebaseInProgress: Bool = false
    ) {
        precondition(!resourceID.isEmpty, "Repository state needs a resource identity")
        self.resourceID = resourceID
        self.availability = availability
        self.branch = branch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? branch : nil
        self.isDetached = isDetached
        self.hasSubmodules = hasSubmodules
        self.isRebaseInProgress = isRebaseInProgress
    }
    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_RefreshRepositoryResourceResult(serializedBytes: protobufBytes)
        guard let availability = RepositoryResourceAvailability(rawValue: message.availability) else {
            throw WireCodecError.invalidRepositoryAvailability(message.availability)
        }
        self.init(
            resourceID: message.resourceID,
            availability: availability,
            branch: message.branch,
            isDetached: message.isDetached,
            hasSubmodules: message.hasSubmodules_p,
            isRebaseInProgress: message.isRebaseInProgress
        )
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_RefreshRepositoryResourceResult()
        message.resourceID = resourceID
        message.availability = availability.rawValue
        if let branch { message.branch = branch }
        message.isDetached = isDetached
        message.hasSubmodules_p = hasSubmodules
        message.isRebaseInProgress = isRebaseInProgress
        return try message.serializedData()
    }
}

public struct ListExecutionContextsQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.execution-context.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let spaceID: String?
    public let resourceID: String?

    public init(spaceID: String? = nil, resourceID: String? = nil) {
        self.spaceID = spaceID
        self.resourceID = resourceID
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListExecutionContextsQuery(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID.isEmpty ? nil : message.spaceID, resourceID: message.resourceID.isEmpty ? nil : message.resourceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListExecutionContextsQuery()
        message.spaceID = spaceID ?? ""
        message.resourceID = resourceID ?? ""
        return try message.serializedData()
    }
}

public struct ListExecutionContextsResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.execution-context.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let contexts: [ExecutionContext]

    public init(contexts: [ExecutionContext]) { self.contexts = contexts }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListExecutionContextsResponse(serializedBytes: protobufBytes)
        contexts = try message.contexts.map { record in
            guard let contextUUID = UUID(uuidString: record.executionContextID), let spaceUUID = UUID(uuidString: record.spaceID) else {
                throw WireCodecError.invalidIdentity(record.executionContextID)
            }
            let resourceID = record.resourceID.isEmpty ? nil : UUID(uuidString: record.resourceID).map(ResourceID.init(rawValue:))
            guard record.resourceID.isEmpty || resourceID != nil else { throw WireCodecError.invalidIdentity(record.resourceID) }
            return ExecutionContext(
                id: ExecutionContextID(rawValue: contextUUID),
                spaceID: SpaceID(rawValue: spaceUUID),
                kind: ExecutionContextKind(rawValue: record.kind),
                resourceID: resourceID
            )
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListExecutionContextsResponse()
        message.contexts = contexts.map { context in
            var record = AizenWireV1_ExecutionContextRecord()
            record.executionContextID = context.id.description
            record.spaceID = context.spaceID.description
            record.resourceID = context.resourceID?.description ?? ""
            record.kind = context.kind.rawValue
            return record
        }
        return try message.serializedData()
    }
}

public struct ListTerminalSessionsQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.terminal-session.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let spaceID: String?
    public init(spaceID: String? = nil) { self.spaceID = spaceID }
    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListTerminalSessionsQuery(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID.isEmpty ? nil : message.spaceID)
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListTerminalSessionsQuery()
        message.spaceID = spaceID ?? ""
        return try message.serializedData()
    }
}

public struct ListTerminalSessionsResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.terminal-session.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let sessions: [TerminalSession]
    public init(sessions: [TerminalSession]) { self.sessions = sessions }
    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListTerminalSessionsResponse(serializedBytes: protobufBytes)
        sessions = try message.sessions.map(terminalSession)
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListTerminalSessionsResponse()
        message.sessions = sessions.map(terminalSessionRecord)
        return try message.serializedData()
    }
}

public struct ListContextFilesQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.context-files.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let executionContextID: String
    public let relativePath: String
    public let includeHidden: Bool

    public init(executionContextID: String, relativePath: String = "", includeHidden: Bool = false) {
        precondition(!executionContextID.isEmpty, "Context file listing requires an execution context")
        self.executionContextID = executionContextID
        self.relativePath = relativePath
        self.includeHidden = includeHidden
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListContextFilesQuery(serializedBytes: protobufBytes)
        guard !message.executionContextID.isEmpty else { throw WireCodecError.invalidIdentity("execution context") }
        self.init(executionContextID: message.executionContextID, relativePath: message.relativePath, includeHidden: message.includeHidden)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListContextFilesQuery()
        message.executionContextID = executionContextID
        message.relativePath = relativePath
        message.includeHidden = includeHidden
        return try message.serializedData()
    }
}

public struct ListContextFilesResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.context-files.list@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let entries: [ContextFileEntry]

    public init(entries: [ContextFileEntry]) { self.entries = entries }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ListContextFilesResponse(serializedBytes: protobufBytes)
        entries = try message.entries.map { record in
            guard !record.relativePath.hasPrefix("/"), !record.name.isEmpty else {
                throw WireCodecError.invalidIdentity("context file entry")
            }
            return .init(relativePath: record.relativePath, name: record.name, isDirectory: record.isDirectory)
        }
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ListContextFilesResponse()
        message.entries = entries.map { entry in
            var record = AizenWireV1_ContextFileEntryRecord()
            record.relativePath = entry.relativePath
            record.name = entry.name
            record.isDirectory = entry.isDirectory
            return record
        }
        return try message.serializedData()
    }
}

public struct ReadContextTextFileQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.context-files.read-text@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let executionContextID: String
    public let relativePath: String
    public init(executionContextID: String, relativePath: String) { precondition(!executionContextID.isEmpty && !relativePath.isEmpty); self.executionContextID = executionContextID; self.relativePath = relativePath }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_ReadContextTextFileQuery(serializedBytes: protobufBytes); guard !m.executionContextID.isEmpty, !m.relativePath.isEmpty else { throw WireCodecError.invalidIdentity("context text file") }; self.init(executionContextID: m.executionContextID, relativePath: m.relativePath) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_ReadContextTextFileQuery(); m.executionContextID = executionContextID; m.relativePath = relativePath; return try m.serializedData() }
}

public struct ReadContextTextFileResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.context-files.read-text@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let relativePath: String
    public let text: String
    public let contentHash: String
    public init(relativePath: String, text: String, contentHash: String) { self.relativePath = relativePath; self.text = text; self.contentHash = contentHash }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_ReadContextTextFileResponse(serializedBytes: protobufBytes); guard !m.relativePath.isEmpty, m.contentHash.count == 64 else { throw WireCodecError.invalidIdentity("context text file") }; self.init(relativePath: m.relativePath, text: m.text, contentHash: m.contentHash) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_ReadContextTextFileResponse(); m.relativePath = relativePath; m.text = text; m.contentHash = contentHash; return try m.serializedData() }
}

public struct CreateTerminalSessionCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.terminal-session.create@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let terminalSessionID: String
    public let spaceID: String
    public let executionContextID: String
    public let title: String?
    public let initialCommand: String?

    public init(terminalSessionID: String, spaceID: String, executionContextID: String, title: String? = nil, initialCommand: String? = nil) {
        self.terminalSessionID = terminalSessionID
        self.spaceID = spaceID
        self.executionContextID = executionContextID
        self.title = title
        self.initialCommand = initialCommand
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_CreateTerminalSessionCommand(serializedBytes: protobufBytes)
        self.init(
            terminalSessionID: message.terminalSessionID,
            spaceID: message.spaceID,
            executionContextID: message.executionContextID,
            title: message.title.isEmpty ? nil : message.title,
            initialCommand: message.initialCommand.isEmpty ? nil : message.initialCommand
        )
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateTerminalSessionCommand()
        message.terminalSessionID = terminalSessionID
        message.spaceID = spaceID
        message.executionContextID = executionContextID
        message.title = title ?? ""
        message.initialCommand = initialCommand ?? ""
        return try message.serializedData()
    }
}

public struct CreateTerminalSessionResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.terminal-session.create@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let session: TerminalSession

    public init(session: TerminalSession) { self.session = session }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_CreateTerminalSessionResult(serializedBytes: protobufBytes)
        guard message.hasSession else { throw WireCodecError.invalidIdentity("terminal session") }
        self.init(session: try terminalSession(from: message.session))
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateTerminalSessionResult()
        message.session = terminalSessionRecord(session)
        return try message.serializedData()
    }
}

public struct AttachTerminalQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.terminal.attach@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let terminalSessionID: String
    public let afterSequence: UInt64
    public let scrollbackBytes: UInt32
    public let columns: UInt32
    public let rows: UInt32
    public init(terminalSessionID: String, afterSequence: UInt64 = 0, scrollbackBytes: UInt32 = 65_536, columns: UInt32 = 0, rows: UInt32 = 0) { self.terminalSessionID = terminalSessionID; self.afterSequence = afterSequence; self.scrollbackBytes = scrollbackBytes; self.columns = columns; self.rows = rows }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_AttachTerminalQuery(serializedBytes: protobufBytes); guard !m.terminalSessionID.isEmpty, (1...1_000_000).contains(m.scrollbackBytes), (m.columns == 0) == (m.rows == 0), m.columns <= 1_000, m.rows <= 1_000 else { throw WireCodecError.invalidIdentity("terminal attach") }; self.init(terminalSessionID: m.terminalSessionID, afterSequence: m.afterSequence, scrollbackBytes: m.scrollbackBytes, columns: m.columns, rows: m.rows) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_AttachTerminalQuery(); m.terminalSessionID = terminalSessionID; m.afterSequence = afterSequence; m.scrollbackBytes = scrollbackBytes; m.columns = columns; m.rows = rows; return try m.serializedData() }
}

public struct AttachTerminalResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.terminal.attach@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false
    public let terminalSessionID: String; public let sequence: UInt64; public let output: Data; public let truncated: Bool
    public init(terminalSessionID: String, sequence: UInt64, output: Data, truncated: Bool) { self.terminalSessionID = terminalSessionID; self.sequence = sequence; self.output = output; self.truncated = truncated }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_AttachTerminalResponse(serializedBytes: protobufBytes); guard !m.terminalSessionID.isEmpty else { throw WireCodecError.invalidIdentity("terminal attach response") }; self.init(terminalSessionID: m.terminalSessionID, sequence: m.sequence, output: m.output, truncated: m.truncated) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_AttachTerminalResponse(); m.terminalSessionID = terminalSessionID; m.sequence = sequence; m.output = output; m.truncated = truncated; return try m.serializedData() }
}

public struct AcquireTerminalControlCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.terminal-control.acquire@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let terminalSessionID: String
    public let leaseSeconds: UInt32
    public init(terminalSessionID: String, leaseSeconds: UInt32 = 60) { self.terminalSessionID = terminalSessionID; self.leaseSeconds = leaseSeconds }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_AcquireTerminalControlCommand(serializedBytes: protobufBytes); guard !m.terminalSessionID.isEmpty else { throw WireCodecError.invalidIdentity("terminal session") }; self.init(terminalSessionID: m.terminalSessionID, leaseSeconds: m.leaseSeconds) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_AcquireTerminalControlCommand(); m.terminalSessionID = terminalSessionID; m.leaseSeconds = leaseSeconds; return try m.serializedData() }
}

public struct ReleaseTerminalControlCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.terminal-control.release@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let terminalSessionID: String
    public init(terminalSessionID: String) { self.terminalSessionID = terminalSessionID }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_ReleaseTerminalControlCommand(serializedBytes: protobufBytes); guard !m.terminalSessionID.isEmpty else { throw WireCodecError.invalidIdentity("terminal session") }; self.init(terminalSessionID: m.terminalSessionID) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_ReleaseTerminalControlCommand(); m.terminalSessionID = terminalSessionID; return try m.serializedData() }
}

public struct TerminalInputCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.terminal.input@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let terminalSessionID: String; public let sequence: UInt64; public let input: Data
    public init(terminalSessionID: String, sequence: UInt64, input: Data) { self.terminalSessionID = terminalSessionID; self.sequence = sequence; self.input = input }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_TerminalInputCommand(serializedBytes: protobufBytes); guard !m.terminalSessionID.isEmpty, m.sequence > 0 else { throw WireCodecError.invalidIdentity("terminal input") }; self.init(terminalSessionID: m.terminalSessionID, sequence: m.sequence, input: m.input) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_TerminalInputCommand(); m.terminalSessionID = terminalSessionID; m.sequence = sequence; m.input = input; return try m.serializedData() }
}

public struct TerminalResizeCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.terminal.resize@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let terminalSessionID: String
    public let sequence: UInt64
    public let columns: UInt32
    public let rows: UInt32

    public init(terminalSessionID: String, sequence: UInt64, columns: UInt32, rows: UInt32) {
        self.terminalSessionID = terminalSessionID
        self.sequence = sequence
        self.columns = columns
        self.rows = rows
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_TerminalResizeCommand(serializedBytes: protobufBytes)
        guard !message.terminalSessionID.isEmpty, message.sequence > 0, message.columns > 0, message.rows > 0 else {
            throw WireCodecError.invalidIdentity("terminal resize")
        }
        self.init(terminalSessionID: message.terminalSessionID, sequence: message.sequence, columns: message.columns, rows: message.rows)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_TerminalResizeCommand()
        message.terminalSessionID = terminalSessionID
        message.sequence = sequence
        message.columns = columns
        message.rows = rows
        return try message.serializedData()
    }
}

public struct TerminalControlLeaseResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.terminal-control.acquire@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let terminalSessionID: String
    public let controllerDeviceID: String
    public let expiresAt: Date

    public init(terminalSessionID: String, controllerDeviceID: String, expiresAt: Date) {
        self.terminalSessionID = terminalSessionID
        self.controllerDeviceID = controllerDeviceID
        self.expiresAt = expiresAt
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_TerminalControlLeaseResult(serializedBytes: protobufBytes)
        guard !message.terminalSessionID.isEmpty, !message.controllerDeviceID.isEmpty, message.expiresAtMillis > 0 else {
            throw WireCodecError.invalidIdentity("terminal control lease")
        }
        self.init(terminalSessionID: message.terminalSessionID, controllerDeviceID: message.controllerDeviceID, expiresAt: Date(timeIntervalSince1970: TimeInterval(message.expiresAtMillis) / 1_000))
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_TerminalControlLeaseResult()
        message.terminalSessionID = terminalSessionID
        message.controllerDeviceID = controllerDeviceID
        message.expiresAtMillis = Int64((expiresAt.timeIntervalSince1970 * 1_000).rounded(.down))
        return try message.serializedData()
    }
}

public struct TerminalOperationResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.terminal.operation@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let terminalSessionID: String
    public let sequence: UInt64

    public init(terminalSessionID: String, sequence: UInt64) {
        self.terminalSessionID = terminalSessionID
        self.sequence = sequence
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_TerminalOperationResult(serializedBytes: protobufBytes)
        guard !message.terminalSessionID.isEmpty else { throw WireCodecError.invalidIdentity("terminal operation") }
        self.init(terminalSessionID: message.terminalSessionID, sequence: message.sequence)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_TerminalOperationResult()
        message.terminalSessionID = terminalSessionID
        message.sequence = sequence
        return try message.serializedData()
    }
}

private func terminalSession(from record: AizenWireV1_TerminalSessionRecord) throws -> TerminalSession {
    guard let sessionUUID = UUID(uuidString: record.sessionID),
          let spaceUUID = UUID(uuidString: record.spaceID) else {
        throw WireCodecError.invalidIdentity(record.sessionID)
    }
    let contextID = record.executionContextID.isEmpty ? nil : UUID(uuidString: record.executionContextID).map(ExecutionContextID.init(rawValue:))
    guard record.executionContextID.isEmpty || contextID != nil else { throw WireCodecError.invalidIdentity(record.executionContextID) }
    return TerminalSession(
        id: SessionID(rawValue: sessionUUID),
        spaceID: SpaceID(rawValue: spaceUUID),
        executionContextID: contextID,
        title: record.title.isEmpty ? nil : record.title,
        tmuxSessionName: record.tmuxSessionName,
        paneID: record.paneID,
        initialCommand: record.initialCommand.isEmpty ? nil : record.initialCommand,
        createdAt: Date(timeIntervalSince1970: TimeInterval(record.createdAtMillis) / 1_000)
    )
}

private func terminalSessionRecord(_ session: TerminalSession) -> AizenWireV1_TerminalSessionRecord {
    var record = AizenWireV1_TerminalSessionRecord()
    record.sessionID = session.id.description
    record.spaceID = session.spaceID.description
    record.executionContextID = session.executionContextID?.description ?? ""
    record.title = session.title ?? ""
    record.tmuxSessionName = session.tmuxSessionName
    record.paneID = session.paneID
    record.initialCommand = session.initialCommand ?? ""
    record.createdAtMillis = Int64((session.createdAt.timeIntervalSince1970 * 1_000).rounded())
    return record
}

public struct CreateLocalFolderContextCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.execution-context.create-local-folder@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let spaceID: String
    public let resourceID: String

    public init(spaceID: String, resourceID: String) {
        precondition(!spaceID.isEmpty && !resourceID.isEmpty, "Context creation requires Space and Resource identities")
        self.spaceID = spaceID
        self.resourceID = resourceID
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_CreateLocalFolderContextCommand(serializedBytes: protobufBytes)
        self.init(spaceID: message.spaceID, resourceID: message.resourceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateLocalFolderContextCommand()
        message.spaceID = spaceID
        message.resourceID = resourceID
        return try message.serializedData()
    }
}

public struct CreateLocalFolderContextResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.execution-context.create-local-folder@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let contextID: String
    public init(contextID: String) { self.contextID = contextID }
    public init(protobufBytes: Data) throws { self.init(contextID: try AizenWireV1_CreateLocalFolderContextResult(serializedBytes: protobufBytes).executionContextID) }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_CreateLocalFolderContextResult()
        message.executionContextID = contextID
        return try message.serializedData()
    }
}

public struct CreateRepositoryCheckoutContextCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.execution-context.create-repository-checkout@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let spaceID: String; public let resourceID: String
    public init(spaceID: String, resourceID: String) { self.spaceID = spaceID; self.resourceID = resourceID }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_CreateRepositoryCheckoutContextCommand(serializedBytes: protobufBytes); self.init(spaceID: m.spaceID, resourceID: m.resourceID) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_CreateRepositoryCheckoutContextCommand(); m.spaceID = spaceID; m.resourceID = resourceID; return try m.serializedData() }
}

public struct CreateRepositoryCheckoutContextResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.execution-context.create-repository-checkout@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let contextID: String
    public init(contextID: String) { self.contextID = contextID }
    public init(protobufBytes: Data) throws { self.init(contextID: try AizenWireV1_CreateRepositoryCheckoutContextResult(serializedBytes: protobufBytes).executionContextID) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_CreateRepositoryCheckoutContextResult(); m.executionContextID = contextID; return try m.serializedData() }
}

public struct CreateLinkedWorktreeContextCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.execution-context.create-linked-worktree@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let spaceID: String; public let resourceID: String; public let destinationPath: String; public let branch: String; public let createBranch: Bool; public let baseBranch: String?
    public init(spaceID: String, resourceID: String, destinationPath: String, branch: String, createBranch: Bool, baseBranch: String? = nil) {
        precondition(!spaceID.isEmpty && !resourceID.isEmpty && destinationPath.hasPrefix("/") && !branch.isEmpty, "Linked worktree creation needs valid identities, destination, and branch")
        self.spaceID = spaceID; self.resourceID = resourceID; self.destinationPath = destinationPath; self.branch = branch; self.createBranch = createBranch; self.baseBranch = baseBranch
    }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_CreateLinkedWorktreeContextCommand(serializedBytes: protobufBytes); self.init(spaceID: m.spaceID, resourceID: m.resourceID, destinationPath: m.destinationPath, branch: m.branch, createBranch: m.createBranch, baseBranch: m.hasBaseBranch ? m.baseBranch : nil) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_CreateLinkedWorktreeContextCommand(); m.spaceID = spaceID; m.resourceID = resourceID; m.destinationPath = destinationPath; m.branch = branch; m.createBranch = createBranch; if let baseBranch { m.baseBranch = baseBranch }; return try m.serializedData() }
}

public struct CreateLinkedWorktreeContextResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.execution-context.create-linked-worktree@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let contextID: String; public let operationID: String
    public init(contextID: String, operationID: String) { self.contextID = contextID; self.operationID = operationID }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_CreateLinkedWorktreeContextResult(serializedBytes: protobufBytes); self.init(contextID: m.executionContextID, operationID: m.operationID) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_CreateLinkedWorktreeContextResult(); m.executionContextID = contextID; m.operationID = operationID; return try m.serializedData() }
}

public enum IndependentContextMode: String, Sendable, Hashable { case clone, copy }

public struct CreateIndependentContextCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.execution-context.create-independent@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let spaceID: String; public let resourceID: String; public let destinationPath: String; public let mode: IndependentContextMode
    public init(spaceID: String, resourceID: String, destinationPath: String, mode: IndependentContextMode) { precondition(!spaceID.isEmpty && !resourceID.isEmpty && destinationPath.hasPrefix("/")); self.spaceID = spaceID; self.resourceID = resourceID; self.destinationPath = destinationPath; self.mode = mode }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_CreateIndependentContextCommand(serializedBytes: protobufBytes); guard let mode = IndependentContextMode(rawValue: m.mode) else { throw WireCodecError.invalidLifecycle(m.mode) }; self.init(spaceID: m.spaceID, resourceID: m.resourceID, destinationPath: m.destinationPath, mode: mode) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_CreateIndependentContextCommand(); m.spaceID = spaceID; m.resourceID = resourceID; m.destinationPath = destinationPath; m.mode = mode.rawValue; return try m.serializedData() }
}

public struct CreateIndependentContextResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.execution-context.create-independent@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let contextID: String; public let operationID: String
    public init(contextID: String, operationID: String) { self.contextID = contextID; self.operationID = operationID }
    public init(protobufBytes: Data) throws { let m = try AizenWireV1_CreateIndependentContextResult(serializedBytes: protobufBytes); self.init(contextID: m.executionContextID, operationID: m.operationID) }
    public func protobufBytes() throws -> Data { var m = AizenWireV1_CreateIndependentContextResult(); m.executionContextID = contextID; m.operationID = operationID; return try m.serializedData() }
}

public struct AttachExecutionContextCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.session.attach-execution-context@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let sessionID: String
    public let contextID: String
    public init(sessionID: String, contextID: String) {
        precondition(!sessionID.isEmpty && !contextID.isEmpty, "Context attachment requires Session and Context identities")
        self.sessionID = sessionID
        self.contextID = contextID
    }
    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_AttachExecutionContextCommand(serializedBytes: protobufBytes)
        self.init(sessionID: message.sessionID, contextID: message.executionContextID)
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_AttachExecutionContextCommand()
        message.sessionID = sessionID
        message.executionContextID = contextID
        return try message.serializedData()
    }
}

public struct RemoveExecutionContextCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.execution-context.remove@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let contextID: String
    public init(contextID: String) { self.contextID = contextID }
    public init(protobufBytes: Data) throws {
        self.init(contextID: try AizenWireV1_RemoveExecutionContextCommand(serializedBytes: protobufBytes).executionContextID)
    }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_RemoveExecutionContextCommand()
        message.executionContextID = contextID
        return try message.serializedData()
    }
}

public struct DetachExecutionContextCommandPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command.session.detach-execution-context@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public let sessionID: String
    public init(sessionID: String) { self.sessionID = sessionID }
    public init(protobufBytes: Data) throws { self.init(sessionID: try AizenWireV1_DetachExecutionContextCommand(serializedBytes: protobufBytes).sessionID) }
    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_DetachExecutionContextCommand()
        message.sessionID = sessionID
        return try message.serializedData()
    }
}

public struct ExecutionContextMutationResultPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.command-result.execution-context.mutation@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true
    public init() {}
    public init(protobufBytes: Data) throws { _ = try AizenWireV1_ExecutionContextMutationResult(serializedBytes: protobufBytes) }
    public func protobufBytes() throws -> Data { try AizenWireV1_ExecutionContextMutationResult().serializedData() }
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

public struct ReadJournalEventsQueryPayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query.journal-events@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = false

    public let afterCursor: UInt64
    public let spaceID: String?

    public init(afterCursor: UInt64, spaceID: String? = nil) {
        self.afterCursor = afterCursor
        self.spaceID = spaceID
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ReadJournalEventsQuery(serializedBytes: protobufBytes)
        self.init(afterCursor: message.afterCursor, spaceID: message.spaceID.isEmpty ? nil : message.spaceID)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ReadJournalEventsQuery()
        message.afterCursor = afterCursor
        message.spaceID = spaceID ?? ""
        return try message.serializedData()
    }
}

public struct ReadJournalEventsResponsePayload: WirePayload, Sendable, Hashable {
    public static let identifier = PayloadIdentifier(rawValue: "aizen.query-result.journal-events@1")
    public static let schemaVersion: UInt32 = 1
    public static let stateAffecting = true

    public let events: [JournalEvent]
    public let oldestCursor: UInt64
    public let latestCursor: UInt64
    public let snapshotRequired: Bool

    public init(events: [JournalEvent], oldestCursor: UInt64, latestCursor: UInt64, snapshotRequired: Bool) {
        self.events = events
        self.oldestCursor = oldestCursor
        self.latestCursor = latestCursor
        self.snapshotRequired = snapshotRequired
    }

    public init(protobufBytes: Data) throws {
        let message = try AizenWireV1_ReadJournalEventsResponse(serializedBytes: protobufBytes)
        let events = try message.events.map { record in
            guard let eventID = UUID(uuidString: record.eventID), record.cursor > 0,
                  !record.aggregateID.isEmpty, !record.aggregateType.isEmpty,
                  !record.payloadIdentifier.isEmpty, record.payloadSchemaVersion > 0,
                  let durability = EventDurability(rawValue: record.durability) else {
                throw WireCodecError.invalidIdentity("journal event")
            }
            let spaceID = try record.spaceID.isEmpty ? nil : SpaceID(rawValue: Self.uuid(from: record.spaceID))
            return JournalEvent(
                id: eventID,
                cursor: record.cursor,
                spaceID: spaceID,
                aggregateID: record.aggregateID,
                aggregateType: record.aggregateType,
                aggregateRevision: record.aggregateRevision,
                occurredAt: Date(timeIntervalSince1970: Double(record.occurredAtMillis) / 1_000),
                payloadIdentifier: record.payloadIdentifier,
                payloadSchemaVersion: record.payloadSchemaVersion,
                payloadBytes: record.payloadBytes,
                durability: durability
            )
        }
        self.init(events: events, oldestCursor: message.oldestCursor, latestCursor: message.latestCursor, snapshotRequired: message.snapshotRequired)
    }

    public func protobufBytes() throws -> Data {
        var message = AizenWireV1_ReadJournalEventsResponse()
        message.events = events.map { event in
            var record = AizenWireV1_JournalEventRecord()
            record.cursor = event.cursor
            record.eventID = event.id.uuidString
            record.spaceID = event.spaceID?.description ?? ""
            record.aggregateID = event.aggregateID
            record.aggregateType = event.aggregateType
            record.aggregateRevision = event.aggregateRevision
            record.occurredAtMillis = Int64((event.occurredAt.timeIntervalSince1970 * 1_000).rounded(.towardZero))
            record.payloadIdentifier = event.payloadIdentifier
            record.payloadSchemaVersion = event.payloadSchemaVersion
            record.payloadBytes = event.payloadBytes
            record.durability = event.durability.rawValue
            return record
        }
        message.oldestCursor = oldestCursor
        message.latestCursor = latestCursor
        message.snapshotRequired = snapshotRequired
        return try message.serializedData()
    }

    private static func uuid(from value: String) throws -> UUID {
        guard let value = UUID(uuidString: value) else { throw WireCodecError.invalidIdentity(value) }
        return value
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
    case invalidURL(String)
    case invalidLifecycle(String)
    case invalidAuthenticationPayload
    case invalidRepositoryAvailability(String)
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
