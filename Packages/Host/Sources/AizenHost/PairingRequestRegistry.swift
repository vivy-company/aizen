import AizenCore
import AizenSecurity
import AizenWire
import Foundation

/// Local-approval view of a remote pairing request. It intentionally excludes the QR secret.
public struct PendingPairingRequest: Sendable, Hashable, Identifiable {
    public let tokenID: UUID
    public let device: DevicePublicIdentity
    public let route: String
    public let receivedAt: Date

    public var id: UUID { tokenID }
}

public enum PairingRequestError: Swift.Error, Sendable, Equatable {
    case wrongHost
    case unsupportedRoute
    case alreadyPending
    case unknownRequest
}

/// Holds a pairing proof only in Host memory until a local approval decision consumes it.
public actor PairingRequestRegistry {
    private struct Pending: Sendable {
        let request: PairingRequestPayload
        let device: DevicePublicIdentity
        let receivedAt: Date
    }

    private let hostID: HostID
    private let approval: PairingApprovalService
    private let lifetime: TimeInterval
    private var requests: [UUID: Pending] = [:]

    public init(hostID: HostID, approval: PairingApprovalService, lifetime: TimeInterval = 300) {
        precondition(lifetime > 0, "Pending pairing lifetime must be positive")
        self.hostID = hostID
        self.approval = approval
        self.lifetime = lifetime
    }

    public func submit(_ request: PairingRequestPayload, now: Date = Date()) throws -> PendingPairingRequest {
        prune(now: now)
        guard request.hostID == hostID else { throw PairingRequestError.wrongHost }
        guard request.route == ConnectionRoute.lan.rawValue else { throw PairingRequestError.unsupportedRoute }
        guard requests[request.tokenID] == nil else { throw PairingRequestError.alreadyPending }
        let device = DevicePublicIdentity(
            deviceID: request.deviceID,
            displayName: request.deviceDisplayName,
            platform: request.devicePlatform,
            cryptographicIdentity: try .init(signingPublicKey: request.deviceSigningPublicKey, keyAgreementPublicKey: request.deviceKeyAgreementPublicKey)
        )
        requests[request.tokenID] = .init(request: request, device: device, receivedAt: now)
        return .init(tokenID: request.tokenID, device: device, route: request.route, receivedAt: now)
    }

    public func pending(now: Date = Date()) -> [PendingPairingRequest] {
        prune(now: now)
        return requests.values.map { .init(tokenID: $0.request.tokenID, device: $0.device, route: $0.request.route, receivedAt: $0.receivedAt) }.sorted { $0.receivedAt < $1.receivedAt }
    }

    public func approve(tokenID: UUID, grants: Set<CapabilityGrant>) async throws -> DeviceAuthorization {
        guard let pending = requests.removeValue(forKey: tokenID) else { throw PairingRequestError.unknownRequest }
        return try await approval.approve(device: pending.device, tokenID: tokenID, secret: pending.request.pairingSecret, grants: grants, route: pending.request.route)
    }

    public func reject(tokenID: UUID) async throws {
        guard let pending = requests.removeValue(forKey: tokenID) else { throw PairingRequestError.unknownRequest }
        try await approval.reject(deviceID: pending.device.deviceID, route: pending.request.route)
    }

    private func prune(now: Date) {
        requests = requests.filter { now.timeIntervalSince($0.value.receivedAt) < lifetime }
    }
}
