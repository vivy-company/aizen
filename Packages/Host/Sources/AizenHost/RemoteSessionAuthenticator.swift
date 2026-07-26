import AizenCore
import AizenSecurity
import AizenStorage
import AizenWire
import Foundation
import Security

public enum RemoteSessionAuthenticationError: Swift.Error, Sendable, Equatable {
    case rejected
    case sessionUnknown
    case sessionExpired
    case randomSourceFailed
}

public struct AuthenticatedRemoteSession: Sendable {
    public let connectionID: UUID
    public let deviceID: DeviceID
    public let route: ConnectionRoute
    public let keys: AuthenticatedConnectionKeys
}

/// Host-only authentication state for one remote connection. Local XPC clients never enter this path.
public actor RemoteSessionAuthenticator {
    private struct PendingSession: Sendable {
        let device: DevicePublicIdentity
        let route: ConnectionRoute
        let binding: ConnectionAuthenticationBinding
        let hostEphemeralKey: ConnectionEphemeralKey
        let expiresAt: Date
    }

    private let host: HostPublicIdentity
    private let hostIdentity: LocalCryptographicIdentity
    private let storage: StorageRepository
    private let pendingLifetime: TimeInterval
    private var pendingSessions: [UUID: PendingSession] = [:]

    public init(host: HostPublicIdentity, hostIdentity: LocalCryptographicIdentity, storage: StorageRepository, pendingLifetime: TimeInterval = 30) {
        precondition(pendingLifetime > 0, "Authentication pending lifetime must be positive")
        precondition(host.cryptographicIdentity == hostIdentity.publicIdentity(createdAt: host.cryptographicIdentity.createdAt), "Host public and private identities must match")
        self.host = host
        self.hostIdentity = hostIdentity
        self.storage = storage
        self.pendingLifetime = pendingLifetime
    }

    public func begin(_ start: AuthenticationStartPayload, protocolGeneration: UInt32 = UInt32(AizenHostModule.protocolGeneration)) async throws -> AuthenticationChallengePayload {
        pruneExpiredSessions(now: Date())
        guard start.hostID == host.hostID, let route = ConnectionRoute(rawValue: start.route) else {
            await auditFailure(deviceID: start.deviceID, route: start.route)
            throw RemoteSessionAuthenticationError.rejected
        }
        guard let authorization = try await storage.deviceAuthorization(for: start.deviceID), authorization.revokedAt == nil,
              authorization.device.cryptographicIdentity.signingPublicKey == start.deviceSigningPublicKey,
              authorization.device.cryptographicIdentity.keyAgreementPublicKey == start.deviceKeyAgreementPublicKey else {
            await auditFailure(deviceID: start.deviceID, route: start.route)
            throw RemoteSessionAuthenticationError.rejected
        }

        do {
            let hostEphemeralKey = ConnectionEphemeralKey()
            let binding = try ConnectionAuthenticationBinding(
                protocolGeneration: protocolGeneration,
                hostID: host.hostID,
                deviceID: start.deviceID,
                connectionID: start.connectionID,
                clientNonce: start.clientNonce,
                serverNonce: try randomNonce(),
                clientEphemeralPublicKey: start.clientEphemeralPublicKey,
                serverEphemeralPublicKey: hostEphemeralKey.publicKey,
                route: route
            )
            let proof = ConnectionAuthenticator.makeProof(participant: .host, identity: hostIdentity, binding: binding)
            pendingSessions[start.connectionID] = PendingSession(
                device: authorization.device,
                route: route,
                binding: binding,
                hostEphemeralKey: hostEphemeralKey,
                expiresAt: Date().addingTimeInterval(pendingLifetime)
            )
            return AuthenticationChallengePayload(
                hostID: host.hostID,
                deviceID: start.deviceID,
                connectionID: start.connectionID,
                clientNonce: binding.clientNonce,
                serverNonce: binding.serverNonce,
                hostSigningPublicKey: host.cryptographicIdentity.signingPublicKey,
                hostKeyAgreementPublicKey: host.cryptographicIdentity.keyAgreementPublicKey,
                serverEphemeralPublicKey: binding.serverEphemeralPublicKey,
                route: route.rawValue,
                hostSignature: proof.signature
            )
        } catch {
            await auditFailure(deviceID: start.deviceID, route: start.route)
            throw error
        }
    }

    public func finish(_ proof: AuthenticationProofPayload) async throws -> AuthenticatedRemoteSession {
        guard let pending = pendingSessions.removeValue(forKey: proof.connectionID) else {
            throw RemoteSessionAuthenticationError.sessionUnknown
        }
        guard pending.expiresAt > Date() else {
            await auditFailure(deviceID: pending.device.deviceID, route: pending.route.rawValue)
            throw RemoteSessionAuthenticationError.sessionExpired
        }
        do {
            try ConnectionAuthenticator.verify(
                .init(participant: .device, signature: proof.deviceSignature),
                expectedParticipant: .device,
                identity: pending.device.cryptographicIdentity,
                binding: pending.binding
            )
            let keys = try ConnectionAuthenticator.deriveKeys(
                participant: .host,
                ephemeralKey: pending.hostEphemeralKey,
                peerEphemeralPublicKey: pending.binding.clientEphemeralPublicKey,
                binding: pending.binding
            )
            return AuthenticatedRemoteSession(connectionID: proof.connectionID, deviceID: pending.device.deviceID, route: pending.route, keys: keys)
        } catch {
            await auditFailure(deviceID: pending.device.deviceID, route: pending.route.rawValue)
            throw error
        }
    }

    private func pruneExpiredSessions(now: Date) {
        pendingSessions = pendingSessions.filter { $0.value.expiresAt > now }
    }

    private func randomNonce() throws -> Data {
        var nonce = Data(count: ConnectionAuthenticationBinding.nonceLength)
        let status = nonce.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw RemoteSessionAuthenticationError.randomSourceFailed }
        return nonce
    }

    private func auditFailure(deviceID: DeviceID, route: String) async {
        try? await storage.appendSecurityAuditRecord(.init(kind: .authenticationFailed, deviceID: deviceID, route: route))
    }
}
