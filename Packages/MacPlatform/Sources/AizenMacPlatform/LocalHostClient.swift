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

    public func renameSpace(id: SpaceID, name: String) async throws {
        try await client.renameSpace(id: id, name: name)
    }

    public func deleteSpace(id: SpaceID) async throws {
        try await client.deleteSpace(id: id)
    }

    public func conversations(in spaceID: SpaceID? = nil) async throws -> [Session] {
        try await client.conversations(spaceID: spaceID)
    }

    public func createConversation(spaceID: SpaceID, title: String) async throws -> SessionID {
        try await client.createConversation(spaceID: spaceID, title: title)
    }

    public func runs(in spaceID: SpaceID? = nil) async throws -> [Run] {
        try await client.runs(spaceID: spaceID)
    }

    public func resources(in spaceID: SpaceID? = nil) async throws -> [Resource] {
        try await client.resources(spaceID: spaceID)
    }

    public func importLocalFolder(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        try await client.importLocalFolder(spaceID: spaceID, path: path, title: title)
    }

    public func importLocalRepository(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        try await client.importLocalRepository(spaceID: spaceID, path: path, title: title)
    }

    public func removeResource(id: ResourceID) async throws {
        try await client.removeResource(id: id)
    }

    public func executionContexts(in spaceID: SpaceID? = nil, resourceID: ResourceID? = nil) async throws -> [ExecutionContext] {
        try await client.executionContexts(spaceID: spaceID, resourceID: resourceID)
    }

    public func createLocalFolderContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await client.createLocalFolderContext(spaceID: spaceID, resourceID: resourceID)
    }

    public func createRepositoryCheckoutContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await client.createRepositoryCheckoutContext(spaceID: spaceID, resourceID: resourceID)
    }

    public func attachExecutionContext(sessionID: SessionID, contextID: ExecutionContextID) async throws {
        try await client.attachExecutionContext(sessionID: sessionID, contextID: contextID)
    }

    public func removeExecutionContext(id: ExecutionContextID) async throws {
        try await client.removeExecutionContext(id: id)
    }

    public func detachExecutionContext(sessionID: SessionID) async throws {
        try await client.detachExecutionContext(sessionID: sessionID)
    }

    public func conversationTimeline(sessionID: SessionID) async throws -> [ConversationMessage] {
        try await client.conversationTimeline(sessionID: sessionID)
    }

    public func cancelRun(id: RunID) async throws {
        try await client.cancelRun(id: id)
    }
}
