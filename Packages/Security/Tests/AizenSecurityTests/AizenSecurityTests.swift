import AizenCore
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
