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
        let snapshot = try JSONDecoder().decode(StorageSnapshot.self, from: try await client.snapshotData())
        return snapshot.runs.filter { spaceID == nil || $0.spaceID == spaceID }
    }

    public func conversationTimeline(sessionID: SessionID) async throws -> [ConversationMessage] {
        try await client.conversationTimeline(sessionID: sessionID)
    }
}
