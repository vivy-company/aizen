import AizenClient
import AizenHost
import AizenStorage
import AizenTransport
import Foundation

/// The app's local v2 Host composition. Views receive Client projections; they never own Storage or Host state.
actor ReignitionHostComposition {
    let storage: StorageRepository
    let host: LocalHost
    let client: HostClient

    init(storageURL: URL? = nil) {
        let storageURL = storageURL ?? ReignitionHostComposition.defaultStorageURL()
        let storage = StorageRepository(url: storageURL)
        self.storage = storage
        host = LocalHost(storage: storage)
        client = HostClient(transport: InProcessTransport(endpoint: host))
    }

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "win.aizen.app", isDirectory: true)
            .appendingPathComponent("Reignition", isDirectory: true)
            .appendingPathComponent("storage-v2.json")
    }

    func snapshot() async throws -> StorageSnapshot {
        try JSONDecoder().decode(StorageSnapshot.self, from: try await client.snapshotData())
    }
}
