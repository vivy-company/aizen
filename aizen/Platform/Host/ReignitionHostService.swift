import Foundation
import ServiceManagement

nonisolated enum ReignitionHostService {
    enum Status: Sendable, Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case missing
        case unknown

        var title: String {
            switch self {
            case .notRegistered: "Not registered"
            case .enabled: "Running when needed"
            case .requiresApproval: "Approval required"
            case .missing: "Bundled service missing"
            case .unknown: "Unknown"
            }
        }

        var detail: String {
            switch self {
            case .notRegistered: "Aizen will register the Host the next time it starts."
            case .enabled: "The Host persists independently of Aizen windows."
            case .requiresApproval: "Allow Aizen Host in System Settings > General > Login Items."
            case .missing: "Reinstall Aizen to restore the bundled Host service."
            case .unknown: "Refresh or repair the Host service to check its state."
            }
        }
    }

    nonisolated static let plistName = "win.aizen.host.plist"
    nonisolated static let machServiceName = "win.aizen.host"

    enum Error: Swift.Error, LocalizedError {
        case missingBundledService
        case requiresApproval

        var errorDescription: String? {
            switch self {
            case .missingBundledService:
                "The bundled Aizen Host LaunchAgent could not be found. Reinstall Aizen to repair it."
            case .requiresApproval:
                "Aizen Host needs approval in System Settings before it can run."
            }
        }
    }

    nonisolated static var service: SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    nonisolated static var status: Status {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .missing
        @unknown default: .unknown
        }
    }

    nonisolated static func registerIfNeeded() throws {
        switch status {
        case .notRegistered:
            try service.register()
            if service.status == .requiresApproval {
                throw Error.requiresApproval
            }
        case .enabled:
            break
        case .requiresApproval:
            throw Error.requiresApproval
        case .missing:
            throw Error.missingBundledService
        case .unknown:
            try service.register()
        }
    }
}
