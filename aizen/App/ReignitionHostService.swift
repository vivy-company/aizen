import Foundation
import ServiceManagement

enum ReignitionHostService {
    static let plistName = "win.aizen.host.plist"

    enum Error: Swift.Error, LocalizedError {
        case missingBundledService

        var errorDescription: String? {
            switch self {
            case .missingBundledService:
                "The bundled Aizen Host LaunchAgent could not be found. Reinstall Aizen to repair it."
            }
        }
    }

    static var service: SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    static func registerIfNeeded() throws {
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
