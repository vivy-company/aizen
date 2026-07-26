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
    let hostKey = try PairedTLSPreSharedKey.derive(hostID: hostID, device: device, hostIdentity: hostIdentity)
    let deviceKey = try deviceIdentity.sharedSecret(with: hostIdentity.publicIdentity()).hkdfDerivedSymmetricKey(
        using: SHA256.self,
        salt: tlsPSKSalt(hostID: hostID, deviceID: device.deviceID),
        sharedInfo: Data("aizen.tls-psk.v1".utf8),
        outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
    #expect(hostKey == deviceKey)
    #expect(PairedTLSPreSharedKey.identity(for: device.deviceID) == Data(device.deviceID.description.utf8))
    let otherHostKey = try PairedTLSPreSharedKey.derive(hostID: HostID(), device: device, hostIdentity: hostIdentity)
    #expect(hostKey != otherHostKey)
}

private func tlsPSKSalt(hostID: HostID, deviceID: DeviceID) -> Data {
    var salt = Data("aizen.tls-psk.salt.v1".utf8)
    for identifier in [hostID.rawValue, deviceID.rawValue] {
        var tuple = identifier.uuid
        withUnsafeBytes(of: &tuple) { salt.append(contentsOf: $0) }
    }
    return Data(SHA256.hash(data: salt))
}
