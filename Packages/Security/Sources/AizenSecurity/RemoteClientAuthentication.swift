import AizenCore
import AizenTransport
import AizenWire
import Foundation
import Security

public enum RemoteClientAuthenticationError: Swift.Error, Sendable, Equatable {
    case malformedHandshake
    case hostIdentityMismatch
}

/// A raw binary request/reply exchange used only while establishing a secure Aizen channel.
public typealias RemoteFrameExchange = @Sendable (Data) async throws -> Data

/// Establishes a Host-pinned, mutually authenticated channel for any user-managed route.
/// Network reachability, TLS hostnames, and third-party access layers are intentionally not trust.
public struct RemoteClientAuthenticator: Sendable {
    private let host: HostPublicIdentity
    private let device: DevicePublicIdentity
    private let deviceIdentity: LocalCryptographicIdentity
    private let route: ConnectionRoute
    private let protocolGeneration: UInt32

    public init(
        host: HostPublicIdentity,
        device: DevicePublicIdentity,
        deviceIdentity: LocalCryptographicIdentity,
        route: ConnectionRoute,
        protocolGeneration: UInt32 = UInt32(AizenWireModule.protocolGeneration)
    ) {
        precondition(device.cryptographicIdentity == deviceIdentity.publicIdentity(createdAt: device.cryptographicIdentity.createdAt), "Device public and private identities must match")
        self.host = host
        self.device = device
        self.deviceIdentity = deviceIdentity
        self.route = route
        self.protocolGeneration = protocolGeneration
    }

    public func authenticate(using exchange: @escaping RemoteFrameExchange) async throws -> AuthenticatedRemoteWireTransport {
        let connectionID = UUID()
        let ephemeralKey = ConnectionEphemeralKey()
        let clientNonce = try randomNonce()
        let start = AuthenticationStartPayload(
            hostID: host.hostID,
            deviceID: device.deviceID,
            connectionID: connectionID,
            clientNonce: clientNonce,
            deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
            deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
            clientEphemeralPublicKey: ephemeralKey.publicKey,
            route: route.rawValue
        )
        let startEnvelope = try ProtocolEnvelope(
            messageID: UUID().uuidString,
            connectionID: connectionID.uuidString,
            connectionSequence: 1,
            kind: .authentication,
            channel: .control,
            payload: .init(start)
        )
        let challengeEnvelope = try ProtocolEnvelope(serializedData: try await exchange(startEnvelope.serializedData()))
        guard challengeEnvelope.kind == .authentication,
              challengeEnvelope.payload.identifier == AuthenticationChallengePayload.identifier else {
            throw RemoteClientAuthenticationError.malformedHandshake
        }
        let challenge = try AuthenticationChallengePayload(protobufBytes: challengeEnvelope.payload.protobufBytes)
        guard challenge.hostID == host.hostID,
              challenge.deviceID == device.deviceID,
              challenge.connectionID == connectionID,
              challenge.clientNonce == clientNonce,
              challenge.hostSigningPublicKey == host.cryptographicIdentity.signingPublicKey,
              challenge.hostKeyAgreementPublicKey == host.cryptographicIdentity.keyAgreementPublicKey,
              challenge.route == route.rawValue else {
            throw RemoteClientAuthenticationError.hostIdentityMismatch
        }
        let binding = try ConnectionAuthenticationBinding(
            protocolGeneration: challengeEnvelope.protocolGeneration,
            hostID: host.hostID,
            deviceID: device.deviceID,
            connectionID: connectionID,
            clientNonce: clientNonce,
            serverNonce: challenge.serverNonce,
            clientEphemeralPublicKey: ephemeralKey.publicKey,
            serverEphemeralPublicKey: challenge.serverEphemeralPublicKey,
            route: route
        )
        try ConnectionAuthenticator.verify(
            .init(participant: .host, signature: challenge.hostSignature),
            expectedParticipant: .host,
            identity: host.cryptographicIdentity,
            binding: binding
        )
        let keys = try ConnectionAuthenticator.deriveKeys(
            participant: .device,
            ephemeralKey: ephemeralKey,
            peerEphemeralPublicKey: challenge.serverEphemeralPublicKey,
            binding: binding
        )
        let channel = AuthenticatedWireChannel(keys: keys, binding: binding)
        let proof = ConnectionAuthenticator.makeProof(participant: .device, identity: deviceIdentity, binding: binding)
        let proofEnvelope = try ProtocolEnvelope(
            messageID: UUID().uuidString,
            connectionID: connectionID.uuidString,
            connectionSequence: 2,
            kind: .authentication,
            channel: .control,
            payload: .init(AuthenticationProofPayload(connectionID: connectionID, deviceSignature: proof.signature))
        )
        let readyEnvelope = try await channel.open(try await exchange(proofEnvelope.serializedData()))
        guard readyEnvelope.kind == .capabilities else {
            throw RemoteClientAuthenticationError.malformedHandshake
        }
        return AuthenticatedRemoteWireTransport(channel: channel, exchange: exchange)
    }

    private func randomNonce() throws -> Data {
        var nonce = Data(count: ConnectionAuthenticationBinding.nonceLength)
        let status = nonce.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw RemoteClientAuthenticationError.malformedHandshake }
        return nonce
    }
}

/// Turns a Host-pinned authenticated channel into the common Wire transport contract.
public actor AuthenticatedRemoteWireTransport: WireTransport {
    private let channel: AuthenticatedWireChannel
    private let exchange: RemoteFrameExchange

    public init(channel: AuthenticatedWireChannel, exchange: @escaping RemoteFrameExchange) {
        self.channel = channel
        self.exchange = exchange
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let frame = try await channel.seal(envelope)
        return try await channel.open(try await exchange(frame))
    }
}
