import AizenMacPlatform
import Dispatch
import Foundation

@MainActor
enum HostService {
    static let machServiceName = "win.aizen.host"
    static let teamIdentifier = "QW4U57CXJX"

    static func serve(storageURL: URL) async throws -> Never {
        let configuration = try HostMachServiceConfiguration(
            machServiceName: machServiceName,
            teamIdentifier: teamIdentifier
        )
        let runtime = LocalHostRuntime(storageURL: storageURL)
        let listener = try runtime.makeMachListener(configuration: configuration)
        let displayName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let credentials = try await HostIdentityStore().loadOrCreateCredentials(displayName: displayName)
        let lanListener = runtime.makeLANListener(credentials: credentials)
        try await lanListener.start()
        withExtendedLifetime((runtime, listener, lanListener)) {
            dispatchMain()
        }
    }
}
