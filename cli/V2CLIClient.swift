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

    func renameSpace(id: SpaceID, name: String) async throws {
        try await client.renameSpace(id: id, name: name)
    }

    func deleteSpace(id: SpaceID) async throws {
        try await client.deleteSpace(id: id)
    }

    func conversations(spaceID: SpaceID? = nil) async throws -> [Session] {
        try await client.conversations(in: spaceID)
    }

    func createConversation(spaceID: SpaceID, title: String) async throws -> SessionID {
        try await client.createConversation(spaceID: spaceID, title: title)
    }

    func conversationTimeline(sessionID: SessionID) async throws -> [ConversationMessage] {
        try await client.conversationTimeline(sessionID: sessionID)
    }

    func runs(spaceID: SpaceID? = nil) async throws -> [Run] {
        try await client.runs(in: spaceID)
    }

    func resources(spaceID: SpaceID? = nil) async throws -> [Resource] {
        try await client.resources(in: spaceID)
    }

    func importLocalFolder(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        try await client.importLocalFolder(spaceID: spaceID, path: path, title: title)
    }

    func importLocalRepository(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        try await client.importLocalRepository(spaceID: spaceID, path: path, title: title)
    }

    func removeResource(id: ResourceID) async throws {
        try await client.removeResource(id: id)
    }

    func executionContexts(spaceID: SpaceID? = nil, resourceID: ResourceID? = nil) async throws -> [ExecutionContext] {
        try await client.executionContexts(in: spaceID, resourceID: resourceID)
    }

    func createLocalFolderContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await client.createLocalFolderContext(spaceID: spaceID, resourceID: resourceID)
    }

    func createRepositoryCheckoutContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await client.createRepositoryCheckoutContext(spaceID: spaceID, resourceID: resourceID)
    }

    func attachExecutionContext(sessionID: SessionID, contextID: ExecutionContextID) async throws {
        try await client.attachExecutionContext(sessionID: sessionID, contextID: contextID)
    }

    func removeExecutionContext(id: ExecutionContextID) async throws {
        try await client.removeExecutionContext(id: id)
    }

    func detachExecutionContext(sessionID: SessionID) async throws {
        try await client.detachExecutionContext(sessionID: sessionID)
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
