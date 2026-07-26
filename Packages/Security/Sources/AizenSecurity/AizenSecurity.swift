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

/// Host-side one-time pairing token authority. It retains only a proof, never the QR secret.
public actor PairingTokenAuthority {
    private struct Record: Sendable {
        let proof: PairingSecretProof
        let expiresAt: Date
    }

    private var records: [UUID: Record] = [:]

    public init() {}

    public func issue(for invitation: PairingInvitation) throws {
        try invitation.validate()
        records[invitation.tokenID] = Record(proof: try PairingSecretProof(secret: invitation.secret), expiresAt: invitation.expiresAt)
    }

    public func consume(tokenID: UUID, secret: Data, now: Date = Date()) throws {
        guard let record = records.removeValue(forKey: tokenID) else { throw SecurityError.pairingTokenUnknown }
        guard record.expiresAt > now else { throw SecurityError.invitationExpired }
        guard record.proof.matches(secret) else { throw SecurityError.pairingTokenRejected }
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

/// Strictly monotonic receive sequence guard for an authenticated connection.
public actor ReplayProtection {
    private var highestAcceptedSequence: UInt64 = 0

    public init() {}

    public func accept(sequence: UInt64) throws {
        guard sequence > highestAcceptedSequence else { throw SecurityError.replayedSequence }
        highestAcceptedSequence = sequence
    }
}
