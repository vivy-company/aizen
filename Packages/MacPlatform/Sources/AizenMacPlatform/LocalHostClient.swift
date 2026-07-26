import AizenClient
import AizenCore
import AizenHost
import AizenStorage
import AizenTransport
import Foundation

/// macOS-only temporary composition until the persistent Host/XPC transport replaces it.
public actor LocalHostClient {
    private let client: HostClient

    public init(storageURL: URL) {
        let storage = StorageRepository(url: storageURL)
        client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    }

    public func spaces() async throws -> [Space] {
        try await client.spaces()
    }

    public func createSpace(name: String, icon: String? = nil, summary: String? = nil) async throws -> SpaceID {
        try await client.createSpace(name: name, icon: icon, summary: summary)
    }
}
