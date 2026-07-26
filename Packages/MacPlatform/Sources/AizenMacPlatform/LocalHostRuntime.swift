import AizenHost
import AizenStorage
import Foundation

/// macOS Host runtime construction shared by the persistent helper and deterministic local tests.
public final class LocalHostRuntime: @unchecked Sendable {
    public let host: LocalHost

    public init(storageURL: URL) {
        let storage = StorageRepository(url: storageURL)
        host = LocalHost(storage: storage, terminalRuntime: TmuxTerminalRuntime())
    }

    public func makeMachListener(configuration: HostMachServiceConfiguration) throws -> MachWireHostListener {
        try MachWireHostListener(configuration: configuration, endpoint: host)
    }
}
