import AizenMacPlatform
import Dispatch
import Foundation

enum HostService {
    static let machServiceName = "win.aizen.host"
    static let teamIdentifier = "QW4U57CXJX"

    static func serve(storageURL: URL) throws -> Never {
        let configuration = try HostMachServiceConfiguration(
            machServiceName: machServiceName,
            teamIdentifier: teamIdentifier
        )
        let runtime = LocalHostRuntime(storageURL: storageURL)
        let listener = try runtime.makeMachListener(configuration: configuration)
        withExtendedLifetime((runtime, listener)) {
            dispatchMain()
        }
    }
}
