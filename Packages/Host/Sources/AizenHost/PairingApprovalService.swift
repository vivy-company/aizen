import AizenCore
import AizenSecurity
import AizenStorage
import Foundation

/// Host-side pairing approval boundary. A valid QR proof never grants access without this explicit approval.
public actor PairingApprovalService {
    private let storage: StorageRepository

    public init(storage: StorageRepository) {
        self.storage = storage
    }

    public func issue(_ invitation: PairingInvitation) async throws {
        try await storage.issuePairingToken(PairingTokenRecord(invitation: invitation))
    }

    public func approve(
        device: DevicePublicIdentity,
        tokenID: UUID,
        secret: Data,
        grants: Set<CapabilityGrant>,
        route: String
    ) async throws -> DeviceAuthorization {
        let authorization = DeviceAuthorization(device: device, grants: grants)
        do {
            try await storage.approvePairing(
                tokenID: tokenID,
                secret: secret,
                authorization: authorization,
                auditRecord: .init(kind: .pairingApproved, deviceID: device.deviceID, route: route)
            )
        } catch {
            try? await storage.appendSecurityAuditRecord(.init(kind: .pairingFailed, deviceID: device.deviceID, route: route))
            throw error
        }
        return authorization
    }

    public func reject(deviceID: DeviceID, route: String) async throws {
        try await storage.appendSecurityAuditRecord(.init(kind: .pairingRejected, deviceID: deviceID, route: route))
    }
}
