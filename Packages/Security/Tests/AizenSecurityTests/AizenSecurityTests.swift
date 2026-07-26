import AizenCore
import AizenWire
import CryptoKit
import Foundation
import Testing
@testable import AizenSecurity

@Test func moduleLoads() { _ = AizenSecurityModule.self }

@Test func cryptographicIdentitySignsAndAgreesOnFreshSecrets() throws {
    let first = LocalCryptographicIdentity()
    let second = LocalCryptographicIdentity()
    let message = Data("aizen pairing".utf8)

    #expect(first.publicIdentity().verifies(signature: first.sign(message), message: message))
    let firstSecret = try first.sharedSecret(with: second.publicIdentity()).withUnsafeBytes { Data($0) }
    let secondSecret = try second.sharedSecret(with: first.publicIdentity()).withUnsafeBytes { Data($0) }
    #expect(firstSecret == secondSecret)
}

@Test func pairingTokenRecordsRetainOnlyProofs() throws {
    let identity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: identity.publicIdentity())
    let secret = Data(repeating: 7, count: 32)
    let invitation = try PairingInvitation(secret: secret, host: host, endpointHints: ["wss://aizen.local"], expiresAt: Date().addingTimeInterval(60))
    let record = try PairingTokenRecord(invitation: invitation)
    #expect(record.tokenID == invitation.tokenID)
    #expect(record.proof.matches(secret))
    #expect(!record.proof.matches(Data(repeating: 8, count: 32)))
}

@Test func authorizationEnforcesCapabilitySpaceAndRevocation() throws {
    let identity = LocalCryptographicIdentity()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: identity.publicIdentity())
    let allowedSpace = SpaceID()
    let otherSpace = SpaceID()
    let resource = ResourceID()
    var authorization = DeviceAuthorization(device: device, grants: [
        CapabilityGrant(capability: .fileRead, spaceIDs: [allowedSpace], resourceIDs: [resource])
    ])

    #expect(authorization.permits(.fileRead, spaceID: allowedSpace, resourceID: resource))
    #expect(!authorization.permits(.fileRead, spaceID: otherSpace, resourceID: resource))
    #expect(!authorization.permits(.fileRead, spaceID: allowedSpace, resourceID: ResourceID()))
    authorization.revokedAt = Date()
    #expect(!authorization.permits(.fileRead, spaceID: allowedSpace, resourceID: resource))
}

@Test func replayProtectionRejectsRepeatedAndOlderFrames() async throws {
    let protection = ReplayProtection()
    try await protection.accept(sequence: 1)
    try await protection.accept(sequence: 4)
    await #expect(throws: SecurityError.replayedSequence) { try await protection.accept(sequence: 4) }
    await #expect(throws: SecurityError.replayedSequence) { try await protection.accept(sequence: 3) }
}

@Test func mutualAuthenticationBindsBothIdentitiesRouteAndFreshSessionKeys() throws {
    let hostIdentity = LocalCryptographicIdentity()
    let deviceIdentity = LocalCryptographicIdentity()
    let hostEphemeral = ConnectionEphemeralKey()
    let deviceEphemeral = ConnectionEphemeralKey()
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: 1,
        hostID: HostID(),
        deviceID: DeviceID(),
        connectionID: UUID(),
        clientNonce: Data(repeating: 1, count: 32),
        serverNonce: Data(repeating: 2, count: 32),
        clientEphemeralPublicKey: deviceEphemeral.publicKey,
        serverEphemeralPublicKey: hostEphemeral.publicKey,
        route: .lan
    )
    let hostProof = ConnectionAuthenticator.makeProof(participant: .host, identity: hostIdentity, binding: binding)
    let deviceProof = ConnectionAuthenticator.makeProof(participant: .device, identity: deviceIdentity, binding: binding)
    try ConnectionAuthenticator.verify(hostProof, expectedParticipant: .host, identity: hostIdentity.publicIdentity(), binding: binding)
    try ConnectionAuthenticator.verify(deviceProof, expectedParticipant: .device, identity: deviceIdentity.publicIdentity(), binding: binding)

    let hostKeys = try ConnectionAuthenticator.deriveKeys(participant: .host, ephemeralKey: hostEphemeral, peerEphemeralPublicKey: deviceEphemeral.publicKey, binding: binding)
    let deviceKeys = try ConnectionAuthenticator.deriveKeys(participant: .device, ephemeralKey: deviceEphemeral, peerEphemeralPublicKey: hostEphemeral.publicKey, binding: binding)
    #expect(hostKeys.outboundKey.withUnsafeBytes { Data($0) } == deviceKeys.inboundKey.withUnsafeBytes { Data($0) })
    #expect(hostKeys.inboundKey.withUnsafeBytes { Data($0) } == deviceKeys.outboundKey.withUnsafeBytes { Data($0) })

    let wrongRoute = try ConnectionAuthenticationBinding(
        protocolGeneration: 1,
        hostID: binding.hostID,
        deviceID: binding.deviceID,
        connectionID: binding.connectionID,
        clientNonce: binding.clientNonce,
        serverNonce: binding.serverNonce,
        clientEphemeralPublicKey: binding.clientEphemeralPublicKey,
        serverEphemeralPublicKey: binding.serverEphemeralPublicKey,
        route: .relay
    )
    #expect(throws: SecurityError.invalidAuthenticationProof) {
        try ConnectionAuthenticator.verify(hostProof, expectedParticipant: .host, identity: hostIdentity.publicIdentity(), binding: wrongRoute)
    }
    #expect(throws: SecurityError.invalidConnectionBinding) {
        try ConnectionAuthenticator.deriveKeys(participant: .host, ephemeralKey: hostEphemeral, peerEphemeralPublicKey: ConnectionEphemeralKey().publicKey, binding: binding)
    }
}

@Test func authenticatedWireChannelEncryptsAndRejectsTamperingOrReplay() async throws {
    let hostEphemeral = ConnectionEphemeralKey()
    let deviceEphemeral = ConnectionEphemeralKey()
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: 1,
        hostID: HostID(),
        deviceID: DeviceID(),
        connectionID: UUID(),
        clientNonce: Data(repeating: 1, count: 32),
        serverNonce: Data(repeating: 2, count: 32),
        clientEphemeralPublicKey: deviceEphemeral.publicKey,
        serverEphemeralPublicKey: hostEphemeral.publicKey,
        route: .lan
    )
    let hostKeys = try ConnectionAuthenticator.deriveKeys(participant: .host, ephemeralKey: hostEphemeral, peerEphemeralPublicKey: deviceEphemeral.publicKey, binding: binding)
    let deviceKeys = try ConnectionAuthenticator.deriveKeys(participant: .device, ephemeralKey: deviceEphemeral, peerEphemeralPublicKey: hostEphemeral.publicKey, binding: binding)
    let host = AuthenticatedWireChannel(keys: hostKeys, binding: binding)
    let device = AuthenticatedWireChannel(keys: deviceKeys, binding: binding)
    let envelope = ProtocolEnvelope(messageID: "authenticated", connectionSequence: 1, kind: .hello, channel: .control, payload: try .init(HelloPayload(minimumProtocolGeneration: 1, maximumProtocolGeneration: 1, productVersion: "2.0.0")))

    let frame = try await host.seal(envelope)
    #expect(try await device.open(frame) == envelope)
    await #expect(throws: SecurityError.replayedSequence) { try await device.open(frame) }

    var tampered = try await host.seal(envelope)
    tampered[tampered.index(before: tampered.endIndex)] ^= 1
    await #expect(throws: SecurityError.malformedAuthenticatedFrame) { try await device.open(tampered) }
}

@Test func pairedTLSPreSharedKeysAreSharedOnlyByThePairedIdentities() throws {
    let hostIdentity = LocalCryptographicIdentity()
    let deviceIdentity = LocalCryptographicIdentity()
    let hostID = HostID()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: deviceIdentity.publicIdentity())
    let host = HostPublicIdentity(hostID: hostID, displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let hostKey = try PairedTLSPreSharedKey.derive(hostID: hostID, device: device, hostIdentity: hostIdentity)
    let deviceKey = try deviceIdentity.sharedSecret(with: hostIdentity.publicIdentity()).hkdfDerivedSymmetricKey(
        using: SHA256.self,
        salt: tlsPSKSalt(hostID: hostID, deviceID: device.deviceID),
        sharedInfo: Data("aizen.tls-psk.v1".utf8),
        outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
    #expect(hostKey == deviceKey)
    let clientKey = try PairedTLSPreSharedKey.derive(host: host, deviceID: device.deviceID, deviceIdentity: deviceIdentity)
    #expect(hostKey == clientKey)
    #expect(PairedTLSPreSharedKey.identity(for: device.deviceID) == Data(device.deviceID.description.utf8))
    let otherHostKey = try PairedTLSPreSharedKey.derive(hostID: HostID(), device: device, hostIdentity: hostIdentity)
    #expect(hostKey != otherHostKey)
}

@Test func remoteClientAuthenticatorPinsTheHostBeforeUsingWireFrames() async throws {
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let deviceIdentity = LocalCryptographicIdentity()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: deviceIdentity.publicIdentity())
    let server = AuthenticatedTestServer(host: host, hostIdentity: hostIdentity, device: device)
    let client = RemoteClientAuthenticator(host: host, device: device, deviceIdentity: deviceIdentity, route: .tailscale)

    let transport = try await client.authenticate { frame in
        try await server.exchange(frame)
    }
    let request = ProtocolEnvelope(messageID: "authenticated-remote", connectionSequence: 1, kind: .hello, channel: .control, payload: try .init(HelloPayload(minimumProtocolGeneration: 1, maximumProtocolGeneration: 1, productVersion: "2.0.0")))
    #expect(try await transport.send(request) == request)
}

@Test func authenticatedRemoteTransportPrioritizesControlAheadOfQueuedBlobChunks() async throws {
    let hostEphemeral = ConnectionEphemeralKey()
    let deviceEphemeral = ConnectionEphemeralKey()
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: 1,
        hostID: HostID(),
        deviceID: DeviceID(),
        connectionID: UUID(),
        clientNonce: Data(repeating: 1, count: 32),
        serverNonce: Data(repeating: 2, count: 32),
        clientEphemeralPublicKey: deviceEphemeral.publicKey,
        serverEphemeralPublicKey: hostEphemeral.publicKey,
        route: .lan
    )
    let server = AuthenticatedWireChannel(keys: try ConnectionAuthenticator.deriveKeys(participant: .host, ephemeralKey: hostEphemeral, peerEphemeralPublicKey: deviceEphemeral.publicKey, binding: binding), binding: binding)
    let client = AuthenticatedWireChannel(keys: try ConnectionAuthenticator.deriveKeys(participant: .device, ephemeralKey: deviceEphemeral, peerEphemeralPublicKey: hostEphemeral.publicKey, binding: binding), binding: binding)
    let gate = SchedulerGate()
    let recorder = ChannelRecorder()
    let transport = AuthenticatedRemoteWireTransport(channel: client) { frame in
        let request = try await server.open(frame)
        await recorder.append(request.channel)
        if request.messageID == "blob-first" { await gate.wait() }
        return try await server.seal(request)
    }
    let first = Task { try await transport.send(testEnvelope(messageID: "blob-first", channel: .blob)) }
    await recorder.waitForCount(1)
    let second = Task { try await transport.send(testEnvelope(messageID: "blob-second", channel: .blob)) }
    let control = Task { try await transport.send(testEnvelope(messageID: "control", channel: .control)) }
    await gate.open()
    _ = try await first.value
    _ = try await second.value
    _ = try await control.value
    #expect(await recorder.channels == [.blob, .control, .blob])
}

private actor AuthenticatedTestServer {
    private let host: HostPublicIdentity
    private let hostIdentity: LocalCryptographicIdentity
    private let device: DevicePublicIdentity
    private var binding: ConnectionAuthenticationBinding?
    private var ephemeralKey: ConnectionEphemeralKey?
    private var channel: AuthenticatedWireChannel?

    init(host: HostPublicIdentity, hostIdentity: LocalCryptographicIdentity, device: DevicePublicIdentity) {
        self.host = host
        self.hostIdentity = hostIdentity
        self.device = device
    }

    func exchange(_ data: Data) async throws -> Data {
        if let channel {
            return try await channel.seal(try await channel.open(data))
        }
        let envelope = try ProtocolEnvelope(serializedData: data)
        if envelope.payload.identifier == AuthenticationStartPayload.identifier {
            let start = try AuthenticationStartPayload(protobufBytes: envelope.payload.protobufBytes)
            let ephemeralKey = ConnectionEphemeralKey()
            let binding = try ConnectionAuthenticationBinding(protocolGeneration: envelope.protocolGeneration, hostID: host.hostID, deviceID: device.deviceID, connectionID: start.connectionID, clientNonce: start.clientNonce, serverNonce: Data(repeating: 4, count: 32), clientEphemeralPublicKey: start.clientEphemeralPublicKey, serverEphemeralPublicKey: ephemeralKey.publicKey, route: .tailscale)
            self.binding = binding
            self.ephemeralKey = ephemeralKey
            let proof = ConnectionAuthenticator.makeProof(participant: .host, identity: hostIdentity, binding: binding)
            return try ProtocolEnvelope(messageID: "challenge", connectionID: start.connectionID.uuidString, connectionSequence: 1, kind: .authentication, channel: .control, correlationID: envelope.messageID, payload: .init(AuthenticationChallengePayload(hostID: host.hostID, deviceID: device.deviceID, connectionID: start.connectionID, clientNonce: start.clientNonce, serverNonce: binding.serverNonce, hostSigningPublicKey: host.cryptographicIdentity.signingPublicKey, hostKeyAgreementPublicKey: host.cryptographicIdentity.keyAgreementPublicKey, serverEphemeralPublicKey: ephemeralKey.publicKey, route: ConnectionRoute.tailscale.rawValue, hostSignature: proof.signature))).serializedData()
        }

        let proof = try AuthenticationProofPayload(protobufBytes: envelope.payload.protobufBytes)
        guard let binding = self.binding, let ephemeralKey = self.ephemeralKey else {
            throw SecurityError.invalidConnectionBinding
        }
        try ConnectionAuthenticator.verify(.init(participant: .device, signature: proof.deviceSignature), expectedParticipant: .device, identity: device.cryptographicIdentity, binding: binding)
        let channel = AuthenticatedWireChannel(keys: try ConnectionAuthenticator.deriveKeys(participant: .host, ephemeralKey: ephemeralKey, peerEphemeralPublicKey: binding.clientEphemeralPublicKey, binding: binding), binding: binding)
        self.channel = channel
        return try await channel.seal(ProtocolEnvelope(messageID: "ready", connectionID: binding.connectionID.uuidString, connectionSequence: 1, kind: .capabilities, channel: .control, correlationID: envelope.messageID, payload: .init(CapabilitiesPayload(identifiers: []))))
    }
}

private actor SchedulerGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}

private actor ChannelRecorder {
    private(set) var channels: [WireChannel] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func append(_ channel: WireChannel) { channels.append(channel); continuation?.resume(); continuation = nil }
    func waitForCount(_ count: Int) async {
        guard channels.count < count else { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

private func testEnvelope(messageID: String, channel: WireChannel) throws -> ProtocolEnvelope {
    try .init(messageID: messageID, connectionSequence: 1, kind: .command, channel: channel, payload: .init(HelloPayload(minimumProtocolGeneration: 1, maximumProtocolGeneration: 1, productVersion: "2.0.0")))
}

private func tlsPSKSalt(hostID: HostID, deviceID: DeviceID) -> Data {
    var salt = Data("aizen.tls-psk.salt.v1".utf8)
    for identifier in [hostID.rawValue, deviceID.rawValue] {
        var tuple = identifier.uuid
        withUnsafeBytes(of: &tuple) { salt.append(contentsOf: $0) }
    }
    return Data(SHA256.hash(data: salt))
}
