import AizenCore
import AizenSecurity
import AizenWire
import Foundation
import Security

/// Establishes an encrypted, Host-pinned channel for a device that is not yet authorized.
/// It deliberately stops before creating any authorization; only `PairingRequestRegistry`
/// may submit the QR proof to the local approval boundary.
public actor PairingSessionAuthenticator {
    private struct Pending: Sendable {
        let deviceID: DeviceID
        let deviceIdentity: PublicCryptographicIdentity
        let binding: ConnectionAuthenticationBinding
        let hostEphemeralKey: ConnectionEphemeralKey
        let expiresAt: Date
    }

    private let host: HostPublicIdentity
    private let hostIdentity: LocalCryptographicIdentity
    private let lifetime: TimeInterval
    private var pending: [UUID: Pending] = [:]

    public init(host: HostPublicIdentity, hostIdentity: LocalCryptographicIdentity, lifetime: TimeInterval = 30) {
        precondition(lifetime > 0, "Pairing authentication lifetime must be positive")
        precondition(host.cryptographicIdentity == hostIdentity.publicIdentity(createdAt: host.cryptographicIdentity.createdAt), "Host public and private identities must match")
        self.host = host
        self.hostIdentity = hostIdentity
        self.lifetime = lifetime
    }

    public func begin(_ start: AuthenticationStartPayload, protocolGeneration: UInt32 = UInt32(AizenHostModule.protocolGeneration)) throws -> AuthenticationChallengePayload {
        prune(now: Date())
        guard pending[start.connectionID] == nil, start.hostID == host.hostID, start.route == ConnectionRoute.lan.rawValue else {
            throw RemoteSessionAuthenticationError.rejected
        }
        let deviceIdentity = try PublicCryptographicIdentity(signingPublicKey: start.deviceSigningPublicKey, keyAgreementPublicKey: start.deviceKeyAgreementPublicKey)
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
            route: .lan
        )
        let proof = ConnectionAuthenticator.makeProof(participant: .host, identity: hostIdentity, binding: binding)
        pending[start.connectionID] = .init(deviceID: start.deviceID, deviceIdentity: deviceIdentity, binding: binding, hostEphemeralKey: hostEphemeralKey, expiresAt: Date().addingTimeInterval(lifetime))
        return AuthenticationChallengePayload(
            hostID: host.hostID,
            deviceID: start.deviceID,
            connectionID: start.connectionID,
            clientNonce: binding.clientNonce,
            serverNonce: binding.serverNonce,
            hostSigningPublicKey: host.cryptographicIdentity.signingPublicKey,
            hostKeyAgreementPublicKey: host.cryptographicIdentity.keyAgreementPublicKey,
            serverEphemeralPublicKey: binding.serverEphemeralPublicKey,
            route: ConnectionRoute.lan.rawValue,
            hostSignature: proof.signature
        )
    }

    public func finish(_ proof: AuthenticationProofPayload) throws -> PairingAuthenticatedSession {
        guard let pending = pending.removeValue(forKey: proof.connectionID) else { throw RemoteSessionAuthenticationError.sessionUnknown }
        guard pending.expiresAt > Date() else { throw RemoteSessionAuthenticationError.sessionExpired }
        try ConnectionAuthenticator.verify(.init(participant: .device, signature: proof.deviceSignature), expectedParticipant: .device, identity: pending.deviceIdentity, binding: pending.binding)
        return .init(
            deviceID: pending.deviceID,
            deviceIdentity: pending.deviceIdentity,
            binding: pending.binding,
            keys: try ConnectionAuthenticator.deriveKeys(participant: .host, ephemeralKey: pending.hostEphemeralKey, peerEphemeralPublicKey: pending.binding.clientEphemeralPublicKey, binding: pending.binding)
        )
    }

    private func prune(now: Date) {
        pending = pending.filter { now < $0.value.expiresAt }
    }

    private func randomNonce() throws -> Data {
        var nonce = Data(count: ConnectionAuthenticationBinding.nonceLength)
        let status = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw RemoteSessionAuthenticationError.randomSourceFailed }
        return nonce
    }
}

public struct PairingAuthenticatedSession: Sendable {
    public let deviceID: DeviceID
    public let deviceIdentity: PublicCryptographicIdentity
    public let binding: ConnectionAuthenticationBinding
    public let keys: AuthenticatedConnectionKeys
}
