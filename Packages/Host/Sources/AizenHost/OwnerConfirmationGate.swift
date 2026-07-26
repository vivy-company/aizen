import AizenCore
import AizenSecurity
import AizenStorage
import Foundation

/// The small, closed set of remote actions that require a device-owner authentication in addition to pairing grants.
public enum OwnerConfirmationAction: String, Sendable, Hashable {
    case terminalControl
    case fileWrite
    case repositoryCommit
    case repositoryPush
    case xcodeBuild
}

/// Metadata shown by a platform-owned confirmation prompt. It deliberately excludes command, file, and terminal content.
public struct OwnerConfirmationRequest: Sendable, Hashable {
    public let deviceID: DeviceID
    public let action: OwnerConfirmationAction
    public let capability: HostCapability
    public let spaceID: SpaceID?
    public let resourceID: ResourceID?
    public let route: String

    public init(deviceID: DeviceID, action: OwnerConfirmationAction, capability: HostCapability, spaceID: SpaceID?, resourceID: ResourceID?, route: String) {
        self.deviceID = deviceID
        self.action = action
        self.capability = capability
        self.spaceID = spaceID
        self.resourceID = resourceID
        self.route = route
    }
}

public enum OwnerConfirmationDecision: Sendable, Equatable {
    case approved
    case denied
    case unavailable
}

/// Implemented by the platform that owns an authenticated local-user session.
public protocol OwnerConfirmationAuthority: Sendable {
    func confirm(_ request: OwnerConfirmationRequest) async -> OwnerConfirmationDecision
}

/// Safe for non-interactive Hosts: protected actions never run without a real platform authority.
public struct DenyingOwnerConfirmationAuthority: OwnerConfirmationAuthority {
    public init() {}

    public func confirm(_ request: OwnerConfirmationRequest) async -> OwnerConfirmationDecision {
        .unavailable
    }
}

public enum OwnerConfirmationError: Swift.Error, Sendable, Equatable {
    case denied(OwnerConfirmationAction)
    case unavailable(OwnerConfirmationAction)
}

/// Audits and enforces explicit local-owner confirmation after capability grants have already been checked.
public actor OwnerConfirmationGate {
    private let storage: StorageRepository
    private let authority: any OwnerConfirmationAuthority

    public init(storage: StorageRepository, authority: any OwnerConfirmationAuthority = DenyingOwnerConfirmationAuthority()) {
        self.storage = storage
        self.authority = authority
    }

    public func require(_ request: OwnerConfirmationRequest) async throws {
        switch await authority.confirm(request) {
        case .approved:
            try await storage.appendSecurityAuditRecord(.init(
                kind: .ownerConfirmationApproved,
                deviceID: request.deviceID,
                route: request.route,
                detail: request.action.rawValue
            ))
        case .denied:
            try await storage.appendSecurityAuditRecord(.init(
                kind: .ownerConfirmationDenied,
                deviceID: request.deviceID,
                route: request.route,
                detail: request.action.rawValue
            ))
            throw OwnerConfirmationError.denied(request.action)
        case .unavailable:
            try await storage.appendSecurityAuditRecord(.init(
                kind: .ownerConfirmationUnavailable,
                deviceID: request.deviceID,
                route: request.route,
                detail: request.action.rawValue
            ))
            throw OwnerConfirmationError.unavailable(request.action)
        }
    }
}
