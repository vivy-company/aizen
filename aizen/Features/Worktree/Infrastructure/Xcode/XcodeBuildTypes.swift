//
//  XcodeBuildTypes.swift
//  aizen
//
//  Xcode build types and models
//

import Foundation

// MARK: - Xcode Project

nonisolated struct XcodeProject: Equatable, Sendable {
    let path: String
    let name: String
    let isWorkspace: Bool
    let schemes: [String]

    var displayName: String {
        name.replacingOccurrences(of: ".xcworkspace", with: "")
            .replacingOccurrences(of: ".xcodeproj", with: "")
    }
}

// MARK: - Destination Types

nonisolated enum DestinationType: String, CaseIterable, Sendable {
    case simulator
    case device
    case mac

    var displayName: String {
        switch self {
        case .simulator: return "Simulators"
        case .device: return "Connected Devices"
        case .mac: return "My Mac"
        }
    }
}

nonisolated struct XcodeDestination: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let type: DestinationType
    let platform: String
    let osVersion: String?
    let isAvailable: Bool

    var displayName: String {
        if let version = osVersion {
            return "\(name) (\(version))"
        }
        return name
    }

    var destinationString: String {
        switch type {
        case .mac:
            return "platform=macOS"
        case .simulator, .device:
            return "id=\(id)"
        }
    }
}

// MARK: - Build Phase

nonisolated enum BuildPhase: Equatable, Sendable {
    case idle
    case building(progress: String?)
    case launching
    case succeeded
    case failed(error: String, log: String)

    var isBuilding: Bool {
        switch self {
        case .building, .launching:
            return true
        default:
            return false
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - Build Result

nonisolated struct BuildResult: Sendable {
    let success: Bool
    let duration: TimeInterval
    let log: String
    let errors: [BuildError]
}

nonisolated struct BuildError: Sendable {
    let file: String?
    let line: Int?
    let column: Int?
    let message: String
    let type: ErrorType

    enum ErrorType: String, Sendable {
        case error
        case warning
        case note
    }
}

// MARK: - JSON Response Types

nonisolated struct XcodeBuildListResponse: Decodable, Sendable {
    let project: ProjectInfo?
    let workspace: WorkspaceInfo?

    nonisolated struct ProjectInfo: Decodable, Sendable {
        let schemes: [String]
        let targets: [String]
        let name: String
    }

    nonisolated struct WorkspaceInfo: Decodable, Sendable {
        let schemes: [String]
        let name: String
    }
}

nonisolated struct SimctlDevicesResponse: Decodable, Sendable {
    let devices: [String: [SimctlDevice]]
}

nonisolated struct SimctlDevice: Decodable, Sendable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool
    let deviceTypeIdentifier: String?

    var isBooted: Bool {
        state == "Booted"
    }
}

// MARK: - DeviceCtl Response Types

nonisolated struct DeviceCtlResponse: Decodable, Sendable {
    let result: DeviceCtlResult
}

nonisolated struct DeviceCtlResult: Decodable, Sendable {
    let devices: [DeviceCtlDevice]
}

nonisolated struct DeviceCtlDevice: Decodable, Sendable {
    let identifier: String
    let deviceProperties: DeviceCtlDeviceProperties
    let hardwareProperties: DeviceCtlHardwareProperties
    let connectionProperties: DeviceCtlConnectionProperties?
}

nonisolated struct DeviceCtlDeviceProperties: Decodable, Sendable {
    let name: String
    let osVersionNumber: String?
}

nonisolated struct DeviceCtlHardwareProperties: Decodable, Sendable {
    let deviceType: String
    let platform: String
    let udid: String?
}

nonisolated struct DeviceCtlConnectionProperties: Decodable, Sendable {
    let pairingState: String?
    let tunnelState: String?
}

// MARK: - Destination Cache Types

nonisolated struct CachedDestinations: Codable, Sendable {
    let destinations: [CachedDestination]

    func toDestinationDict() -> [DestinationType: [XcodeDestination]] {
        var result: [DestinationType: [XcodeDestination]] = [:]
        for cached in destinations {
            let dest = cached.toDestination()
            result[cached.type, default: []].append(dest)
        }
        return result
    }
}

nonisolated struct CachedDestination: Codable, Sendable {
    let id: String
    let name: String
    let type: DestinationType
    let platform: String
    let osVersion: String?
    let isAvailable: Bool

    init(destination: XcodeDestination, type: DestinationType) {
        self.id = destination.id
        self.name = destination.name
        self.type = type
        self.platform = destination.platform
        self.osVersion = destination.osVersion
        self.isAvailable = destination.isAvailable
    }

    func toDestination() -> XcodeDestination {
        XcodeDestination(
            id: id,
            name: name,
            type: type,
            platform: platform,
            osVersion: osVersion,
            isAvailable: isAvailable
        )
    }
}

extension DestinationType: Codable {}
