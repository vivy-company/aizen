import AizenCore
import AizenSecurity
import AizenStorage
import Foundation

public enum DeviceAuthorizationError: Swift.Error, Sendable, Equatable {
    case deviceNotPaired
    case capabilityDenied(HostCapability)
}

/// Host-side authorization check used at every authenticated remote-command boundary.
public actor DeviceAuthorizationGate {
    private let storage: StorageRepository

    public init(storage: StorageRepository) {
        self.storage = storage
    }

    public func require(
        deviceID: DeviceID,
        capability: HostCapability,
        spaceID: SpaceID? = nil,
        resourceID: ResourceID? = nil,
        route: String
    ) async throws {
        guard let authorization = try await storage.deviceAuthorization(for: deviceID) else {
            try await recordDenial(deviceID: deviceID, route: route, detail: "unpaired")
            throw DeviceAuthorizationError.deviceNotPaired
        }
        guard authorization.permits(capability, spaceID: spaceID, resourceID: resourceID) else {
            try await recordDenial(deviceID: deviceID, route: route, detail: capability.rawValue)
            throw DeviceAuthorizationError.capabilityDenied(capability)
        }
    }

    private func recordDenial(deviceID: DeviceID, route: String, detail: String) async throws {
        try await storage.appendSecurityAuditRecord(SecurityAuditRecord(
            kind: .authorizationDenied,
            deviceID: deviceID,
            route: route,
            detail: detail
        ))
    }
}
