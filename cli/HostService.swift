import AizenMacPlatform
import Foundation

@MainActor
enum HostService {
    nonisolated static let machServiceName = "win.aizen.host"
    static let teamIdentifier = "QW4U57CXJX"

    static func serve(storageURL: URL) async throws -> Never {
        do {
            let configuration = try HostMachServiceConfiguration(
                machServiceName: machServiceName,
                teamIdentifier: teamIdentifier,
                allowsDevelopmentClients: developmentClientsAreAllowed
            )
            let displayName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            let credentials = try await HostIdentityStore().loadOrCreateCredentials(displayName: displayName)
            let runtime = LocalHostRuntime(storageURL: storageURL, credentials: credentials)
            _ = try await runtime.recoverInterruptedOperations()
            _ = try? await runtime.recoverTerminalSessions()
            let listener = try runtime.makeMachListener(configuration: configuration)
            let lanListener = runtime.makeLANListener(credentials: credentials)
            try await lanListener.start()
            try HostStartupStatusStore.clearFailure(storageURL: storageURL)

            // The Host runs from the CLI's async entry point, which is main-actor isolated.
            // Suspending keeps its listeners alive without blocking the main dispatch queue.
            let lifetime = AsyncStream<Void>.makeStream()
            defer {
                lifetime.continuation.finish()
                withExtendedLifetime((runtime, listener, lanListener)) {}
            }
            for await _ in lifetime.stream {
                // This stream is intentionally never yielded to or finished while the Host runs.
            }
            fatalError("The Host service lifetime ended unexpectedly.")
        } catch {
            try? HostStartupStatusStore.recordFailure(error, storageURL: storageURL)
            throw error
        }
    }

    private static var developmentClientsAreAllowed: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
