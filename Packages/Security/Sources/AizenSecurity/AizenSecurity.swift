import AizenCore
import CryptoKit
import Foundation

/// Platform-neutral identity, pairing, authorization, and replay-protection primitives.
public enum AizenSecurityModule {}

public enum SecurityError: Swift.Error, Sendable, Equatable {
    case malformedKey
    case malformedPairingSecret
    case invitationExpired
    case pairingTokenUnknown
    case pairingTokenRejected
    case invalidConnectionBinding
    case invalidAuthenticationProof
    case replayedSequence
}

public struct IdentityFingerprint: Codable, Sendable, Hashable, CustomStringConvertible {
    public let value: String

    public init(signingPublicKey: Data, keyAgreementPublicKey: Data) {
        let material = signingPublicKey + keyAgreementPublicKey
        value = SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { value }

    public var prefix: String { String(value.prefix(12)) }
}

public struct PublicCryptographicIdentity: Codable, Sendable, Hashable {
    public let signingPublicKey: Data
    public let keyAgreementPublicKey: Data
    public let createdAt: Date

    public init(signingPublicKey: Data, keyAgreementPublicKey: Data, createdAt: Date = Date()) throws {
        guard (try? Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey)) != nil,
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyAgreementPublicKey)) != nil else {
            throw SecurityError.malformedKey
        }
        self.signingPublicKey = signingPublicKey
        self.keyAgreementPublicKey = keyAgreementPublicKey
        self.createdAt = createdAt
    }

    public var fingerprint: IdentityFingerprint {
        IdentityFingerprint(signingPublicKey: signingPublicKey, keyAgreementPublicKey: keyAgreementPublicKey)
    }

    public func verifies(signature: Data, message: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey) else { return false }
        return key.isValidSignature(signature, for: message)
    }
}

public struct HostPublicIdentity: Codable, Sendable, Hashable {
    public let hostID: HostID
    public let displayName: String
    public let cryptographicIdentity: PublicCryptographicIdentity

    public init(hostID: HostID, displayName: String, cryptographicIdentity: PublicCryptographicIdentity) {
        self.hostID = hostID
        self.displayName = displayName
        self.cryptographicIdentity = cryptographicIdentity
    }
}

public struct DevicePublicIdentity: Codable, Sendable, Hashable {
    public let deviceID: DeviceID
    public let displayName: String
    public let platform: String
    public let cryptographicIdentity: PublicCryptographicIdentity

    public init(deviceID: DeviceID, displayName: String, platform: String, cryptographicIdentity: PublicCryptographicIdentity) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.platform = platform
        self.cryptographicIdentity = cryptographicIdentity
    }
}

/// Private key material is intentionally non-Codable. Platform code persists it in Keychain/Secure Enclave.
public struct LocalCryptographicIdentity: Sendable {
    private let signingKey: Curve25519.Signing.PrivateKey
    private let keyAgreementKey: Curve25519.KeyAgreement.PrivateKey

    public init() {
        signingKey = Curve25519.Signing.PrivateKey()
        keyAgreementKey = Curve25519.KeyAgreement.PrivateKey()
    }

    public init(signingPrivateKey: Data, keyAgreementPrivateKey: Data) throws {
        do {
            signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
            keyAgreementKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: keyAgreementPrivateKey)
        } catch {
            throw SecurityError.malformedKey
        }
    }

    public var signingPrivateKey: Data { signingKey.rawRepresentation }
    public var keyAgreementPrivateKey: Data { keyAgreementKey.rawRepresentation }

    public func publicIdentity(createdAt: Date = Date()) -> PublicCryptographicIdentity {
        // Curve25519 keys generated above are always valid public-key encodings.
        try! PublicCryptographicIdentity(
            signingPublicKey: signingKey.publicKey.rawRepresentation,
            keyAgreementPublicKey: keyAgreementKey.publicKey.rawRepresentation,
            createdAt: createdAt
        )
    }

    public func sign(_ message: Data) -> Data {
        try! signingKey.signature(for: message)
    }

    public func sharedSecret(with peer: PublicCryptographicIdentity) throws -> SharedSecret {
        do {
            let key = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer.keyAgreementPublicKey)
            return try keyAgreementKey.sharedSecretFromKeyAgreement(with: key)
        } catch {
            throw SecurityError.malformedKey
        }
    }
}

public struct PairingSecretProof: Codable, Sendable, Hashable {
    public let digest: Data

    public init(secret: Data) throws {
        guard secret.count >= 32 else { throw SecurityError.malformedPairingSecret }
        digest = Data(SHA256.hash(data: secret))
    }

    public func matches(_ secret: Data) -> Bool {
        guard let candidate = try? Self(secret: secret) else { return false }
        return digest == candidate.digest
    }
}

public struct PairingInvitation: Codable, Sendable, Hashable {
    public static let formatVersion = 1

    public let formatVersion: Int
    public let tokenID: UUID
    public let secret: Data
    public let host: HostPublicIdentity
    public let endpointHints: [String]
    public let expiresAt: Date

    public init(tokenID: UUID = UUID(), secret: Data, host: HostPublicIdentity, endpointHints: [String], expiresAt: Date) throws {
        guard secret.count >= 32 else { throw SecurityError.malformedPairingSecret }
        self.formatVersion = Self.formatVersion
        self.tokenID = tokenID
        self.secret = secret
        self.host = host
        self.endpointHints = endpointHints
        self.expiresAt = expiresAt
    }

    public func validate(now: Date = Date()) throws {
        guard formatVersion == Self.formatVersion, expiresAt > now else { throw SecurityError.invitationExpired }
    }
}

/// The Host persists this proof record; the QR secret is never written to disk.
public struct PairingTokenRecord: Codable, Sendable, Hashable {
    public let tokenID: UUID
    public let proof: PairingSecretProof
    public let expiresAt: Date

    public init(invitation: PairingInvitation, now: Date = Date()) throws {
        try invitation.validate(now: now)
        tokenID = invitation.tokenID
        proof = try PairingSecretProof(secret: invitation.secret)
        expiresAt = invitation.expiresAt
    }
}

public enum HostCapability: String, Codable, Sendable, Hashable, CaseIterable {
    case hostRead
    case spaceRead
    case sessionRead
    case resourceRead
    case conversationSend
    case conversationCancel
    case permissionRespond
    case terminalRead
    case terminalControl
    case terminalCreate
    case fileRead
    case fileWrite
    case gitRead
    case gitStage
    case gitCommit
    case gitPull
    case gitPush
    case xcodeRead
    case xcodeBuild
    case hostAdmin
}

public struct CapabilityGrant: Codable, Sendable, Hashable {
    public let capability: HostCapability
    /// Nil means every Space; an empty set grants no Space-scoped access.
    public let spaceIDs: Set<SpaceID>?
    /// Nil means every Resource within allowed Spaces; an empty set grants no Resource-scoped access.
    public let resourceIDs: Set<ResourceID>?

    public init(capability: HostCapability, spaceIDs: Set<SpaceID>? = nil, resourceIDs: Set<ResourceID>? = nil) {
        self.capability = capability
        self.spaceIDs = spaceIDs
        self.resourceIDs = resourceIDs
    }

    func permits(capability: HostCapability, spaceID: SpaceID?, resourceID: ResourceID?) -> Bool {
        guard self.capability == capability else { return false }
        if let spaceIDs {
            guard let spaceID, spaceIDs.contains(spaceID) else { return false }
        }
        if let resourceIDs {
            guard let resourceID, resourceIDs.contains(resourceID) else { return false }
        }
        return true
    }
}

public struct DeviceAuthorization: Codable, Sendable, Hashable {
    public let device: DevicePublicIdentity
    public var grants: Set<CapabilityGrant>
    public var revokedAt: Date?

    public init(device: DevicePublicIdentity, grants: Set<CapabilityGrant> = [], revokedAt: Date? = nil) {
        self.device = device
        self.grants = grants
        self.revokedAt = revokedAt
    }

    public func permits(_ capability: HostCapability, spaceID: SpaceID? = nil, resourceID: ResourceID? = nil) -> Bool {
        guard revokedAt == nil else { return false }
        return grants.contains { $0.permits(capability: capability, spaceID: spaceID, resourceID: resourceID) }
    }
}

/// Audit metadata never carries prompt, filesystem, or terminal content.
public enum SecurityAuditKind: String, Codable, Sendable, Hashable {
    case pairingApproved
    case pairingRejected
    case pairingFailed
    case deviceRevoked
    case authorizationDenied
    case authorizationChanged
    case authenticationFailed
}

public struct SecurityAuditRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let occurredAt: Date
    public let kind: SecurityAuditKind
    public let deviceID: DeviceID?
    public let route: String?
    public let detail: String?

    public init(id: UUID = UUID(), occurredAt: Date = Date(), kind: SecurityAuditKind, deviceID: DeviceID? = nil, route: String? = nil, detail: String? = nil) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.deviceID = deviceID
        self.route = route
        self.detail = detail
    }
}

public enum ConnectionRoute: String, Codable, Sendable, Hashable {
    case lan
    case loopback
    case tailscale
    case cloudflare
    case relay
}

/// The complete context that both identities sign before a connection can carry Host messages.
public struct ConnectionAuthenticationBinding: Sendable, Hashable {
    public static let nonceLength = 32
    public static let ephemeralPublicKeyLength = 32

    public let protocolGeneration: UInt32
    public let hostID: HostID
    public let deviceID: DeviceID
    public let connectionID: UUID
    public let clientNonce: Data
    public let serverNonce: Data
    public let clientEphemeralPublicKey: Data
    public let serverEphemeralPublicKey: Data
    public let route: ConnectionRoute

    public init(
        protocolGeneration: UInt32,
        hostID: HostID,
        deviceID: DeviceID,
        connectionID: UUID,
        clientNonce: Data,
        serverNonce: Data,
        clientEphemeralPublicKey: Data,
        serverEphemeralPublicKey: Data,
        route: ConnectionRoute
    ) throws {
        guard protocolGeneration > 0,
              clientNonce.count == Self.nonceLength,
              serverNonce.count == Self.nonceLength,
              clientEphemeralPublicKey.count == Self.ephemeralPublicKeyLength,
              serverEphemeralPublicKey.count == Self.ephemeralPublicKeyLength,
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientEphemeralPublicKey)) != nil,
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverEphemeralPublicKey)) != nil else {
            throw SecurityError.invalidConnectionBinding
        }
        self.protocolGeneration = protocolGeneration
        self.hostID = hostID
        self.deviceID = deviceID
        self.connectionID = connectionID
        self.clientNonce = clientNonce
        self.serverNonce = serverNonce
        self.clientEphemeralPublicKey = clientEphemeralPublicKey
        self.serverEphemeralPublicKey = serverEphemeralPublicKey
        self.route = route
    }

    public func digest() -> Data {
        var message = Data("aizen.connection-authentication.v1".utf8)
        append(protocolGeneration, to: &message)
        append(hostID.rawValue, to: &message)
        append(deviceID.rawValue, to: &message)
        append(connectionID, to: &message)
        message.append(clientNonce)
        message.append(serverNonce)
        message.append(clientEphemeralPublicKey)
        message.append(serverEphemeralPublicKey)
        let routeBytes = Data(route.rawValue.utf8)
        message.append(UInt8(routeBytes.count))
        message.append(routeBytes)
        return Data(SHA256.hash(data: message))
    }

    private func append(_ value: UInt32, to message: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { message.append(contentsOf: $0) }
    }

    private func append(_ value: UUID, to message: inout Data) {
        var tuple = value.uuid
        withUnsafeBytes(of: &tuple) { message.append(contentsOf: $0) }
    }
}

public enum ConnectionParticipant: String, Codable, Sendable, Hashable {
    case host
    case device
}

public struct ConnectionAuthenticationProof: Sendable, Hashable {
    public let participant: ConnectionParticipant
    public let signature: Data

    public init(participant: ConnectionParticipant, signature: Data) {
        self.participant = participant
        self.signature = signature
    }
}

/// Ephemeral X25519 key material exists only for the lifetime of one authenticated connection.
public struct ConnectionEphemeralKey: Sendable {
    private let privateKey: Curve25519.KeyAgreement.PrivateKey

    public init() {
        privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    public var publicKey: Data { privateKey.publicKey.rawRepresentation }

    fileprivate func sharedSecret(with peerPublicKey: Data) throws -> SharedSecret {
        do {
            return try privateKey.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: peerPublicKey))
        } catch {
            throw SecurityError.invalidConnectionBinding
        }
    }
}

/// Directional symmetric keys derived with X25519 and HKDF-SHA256 after both signed proofs verify.
public struct AuthenticatedConnectionKeys: Sendable {
    public let outboundKey: SymmetricKey
    public let inboundKey: SymmetricKey

    fileprivate init(outboundKey: SymmetricKey, inboundKey: SymmetricKey) {
        self.outboundKey = outboundKey
        self.inboundKey = inboundKey
    }
}

public enum ConnectionAuthenticator {
    public static func makeProof(
        participant: ConnectionParticipant,
        identity: LocalCryptographicIdentity,
        binding: ConnectionAuthenticationBinding
    ) -> ConnectionAuthenticationProof {
        ConnectionAuthenticationProof(participant: participant, signature: identity.sign(signingMessage(participant: participant, binding: binding)))
    }

    public static func verify(
        _ proof: ConnectionAuthenticationProof,
        expectedParticipant: ConnectionParticipant,
        identity: PublicCryptographicIdentity,
        binding: ConnectionAuthenticationBinding
    ) throws {
        guard proof.participant == expectedParticipant,
              identity.verifies(signature: proof.signature, message: signingMessage(participant: expectedParticipant, binding: binding)) else {
            throw SecurityError.invalidAuthenticationProof
        }
    }

    public static func deriveKeys(
        participant: ConnectionParticipant,
        ephemeralKey: ConnectionEphemeralKey,
        peerEphemeralPublicKey: Data,
        binding: ConnectionAuthenticationBinding
    ) throws -> AuthenticatedConnectionKeys {
        let expectedLocalKey: Data
        let expectedPeerKey: Data
        switch participant {
        case .host:
            expectedLocalKey = binding.serverEphemeralPublicKey
            expectedPeerKey = binding.clientEphemeralPublicKey
        case .device:
            expectedLocalKey = binding.clientEphemeralPublicKey
            expectedPeerKey = binding.serverEphemeralPublicKey
        }
        guard ephemeralKey.publicKey == expectedLocalKey, peerEphemeralPublicKey == expectedPeerKey else {
            throw SecurityError.invalidConnectionBinding
        }
        let sharedSecret = try ephemeralKey.sharedSecret(with: peerEphemeralPublicKey)
        let material = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: binding.digest(),
            sharedInfo: Data("aizen.connection-keys.v1".utf8),
            outputByteCount: 64
        )
        let bytes = material.withUnsafeBytes { Data($0) }
        let hostToDevice = SymmetricKey(data: bytes.prefix(32))
        let deviceToHost = SymmetricKey(data: bytes.suffix(32))
        switch participant {
        case .host: return .init(outboundKey: hostToDevice, inboundKey: deviceToHost)
        case .device: return .init(outboundKey: deviceToHost, inboundKey: hostToDevice)
        }
    }

    private static func signingMessage(participant: ConnectionParticipant, binding: ConnectionAuthenticationBinding) -> Data {
        Data("aizen.connection-proof.\(participant.rawValue).v1".utf8) + binding.digest()
    }
}

/// Strictly monotonic receive sequence guard for an authenticated connection.
public actor ReplayProtection {
    private var highestAcceptedSequence: UInt64 = 0

    public init() {}

    public func accept(sequence: UInt64) throws {
        guard sequence > highestAcceptedSequence else { throw SecurityError.replayedSequence }
        highestAcceptedSequence = sequence
    }
}
