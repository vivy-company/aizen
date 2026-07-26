import AizenCore
import AizenSecurity
import AizenStorage
import Foundation

/// Host-side pairing approval boundary. A valid QR proof never grants access without this explicit approval.
public actor PairingApprovalService {
    private let tokens: PairingTokenAuthority
    private let storage: StorageRepository

    public init(tokens: PairingTokenAuthority, storage: StorageRepository) {
        self.tokens = tokens
        self.storage = storage
    }

    public func issue(_ invitation: PairingInvitation) async throws {
        try await tokens.issue(for: invitation)
    }

    public func approve(
        device: DevicePublicIdentity,
        tokenID: UUID,
        secret: Data,
        grants: Set<CapabilityGrant>,
        route: String
    ) async throws -> DeviceAuthorization {
        try await tokens.consume(tokenID: tokenID, secret: secret)
        let authorization = DeviceAuthorization(device: device, grants: grants)
        try await storage.saveDeviceAuthorization(authorization)
        try await storage.appendSecurityAuditRecord(.init(kind: .pairingApproved, deviceID: device.deviceID, route: route))
        return authorization
    }

    public func reject(deviceID: DeviceID, route: String) async throws {
        try await storage.appendSecurityAuditRecord(.init(kind: .pairingRejected, deviceID: deviceID, route: route))
    }
}
