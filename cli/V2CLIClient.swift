import AizenCore
import AizenMacPlatform
import Foundation

/// CLI composition for the local v2 Host. The CLI stays a client and never opens v2 files directly.
actor V2CLIClient {
    private let client: LocalHostClient

    init(storageURL: URL? = nil) {
        client = LocalHostClient(storageURL: storageURL ?? Self.defaultStorageURL())
    }

    func spaces() async throws -> [Space] {
        try await client.spaces()
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
