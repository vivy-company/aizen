@testable import Aizen
import AizenCore
import AizenSecurity
import Foundation
import Testing

@Test func pairingInvitationAcceptsRawAndDeepLinkForms() throws {
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    let invitation = try PairingInvitation(secret: Data(repeating: 7, count: 32), host: host, endpointHints: ["wss://aizen.local"], expiresAt: Date().addingTimeInterval(60))
    let encoded = try JSONEncoder().encode(invitation).base64EncodedString()

    #expect(try MobilePairingInvitation.decode(encoded) == invitation)
    #expect(try MobilePairingInvitation.decode("aizen://pair?invitation=\(encoded)") == invitation)
    #expect(try MobilePairingInvitation.endpoint(from: invitation).absoluteString == "wss://aizen.local")
}

@Test func pairingInvitationRejectsInvalidAndExpiredData() throws {
    #expect(throws: Error.self) { try MobilePairingInvitation.decode("not-an-invitation") }
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    let expired = try PairingInvitation(secret: Data(repeating: 7, count: 32), host: host, endpointHints: ["wss://aizen.local"], expiresAt: Date().addingTimeInterval(-1))
    let encoded = try JSONEncoder().encode(expired).base64EncodedString()
    #expect(throws: SecurityError.invitationExpired) { try MobilePairingInvitation.decode(encoded) }
}
