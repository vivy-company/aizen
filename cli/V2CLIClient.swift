import AizenClient
import AizenHost
import AizenStorage
import AizenTransport
import Foundation

/// CLI composition for the local v2 Host. The CLI stays a client and never opens v2 files directly.
actor V2CLIClient {
    private let client: HostClient

    init(storageURL: URL? = nil) {
        let storage = StorageRepository(url: storageURL ?? Self.defaultStorageURL())
        let host = LocalHost(storage: storage)
        client = HostClient(transport: InProcessTransport(endpoint: host))
    }

    func snapshot() async throws -> StorageSnapshot {
        try JSONDecoder().decode(StorageSnapshot.self, from: try await client.snapshotData())
    }

    func createSpace(name: String, icon: String?) async throws {
        _ = try await client.createSpace(name: name, icon: icon)
    }

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["AIZEN_V2_STORE_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath).standardizedFileURL
        }

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("win.aizen.app", isDirectory: true)
            .appendingPathComponent("Reignition", isDirectory: true)
            .appendingPathComponent("storage-v2.json")
    }
}
