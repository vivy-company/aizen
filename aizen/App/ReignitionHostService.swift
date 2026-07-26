import Foundation
import ServiceManagement

nonisolated enum ReignitionHostService {
    nonisolated static let plistName = "win.aizen.host.plist"
    nonisolated static let machServiceName = "win.aizen.host"

    enum Error: Swift.Error, LocalizedError {
        case missingBundledService

        var errorDescription: String? {
            switch self {
            case .missingBundledService:
                "The bundled Aizen Host LaunchAgent could not be found. Reinstall Aizen to repair it."
            }
        }
    }

    nonisolated static var service: SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    nonisolated static func registerIfNeeded() throws {
        switch service.status {
        case .notRegistered:
            try service.register()
        case .enabled, .requiresApproval:
            break
        case .notFound:
            throw Error.missingBundledService
        @unknown default:
            break
        }
    }
}
