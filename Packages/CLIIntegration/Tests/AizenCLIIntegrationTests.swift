@testable import AizenCLIIntegration
import AizenClient
import AizenCore
import AizenHost
import AizenStorage
import AizenTransport
import Foundation
import Testing

@Test func cliMutatesAndQueriesAnInProcessHostWithoutMacClient() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Project", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let host = LocalHost(storage: storage)
    let cli = V2CLIClient(client: HostClient(transport: InProcessTransport(endpoint: host)))

    try await cli.createSpace(name: "CLI", icon: nil)
    let listedSpaces = try await cli.spaces()
    let space = try #require(listedSpaces.first)
    let resourceID = try await cli.importLocalFolder(spaceID: space.id, path: folder.path, title: "Project")
    let contextID = try await cli.createLocalFolderContext(spaceID: space.id, resourceID: resourceID)
    let conversationID = try await cli.createConversation(spaceID: space.id, title: "CLI conversation")
    try await cli.attachExecutionContext(sessionID: conversationID, contextID: contextID)

    #expect(try await cli.resources(spaceID: space.id).map(\.id) == [resourceID])
    #expect(try await cli.executionContexts(spaceID: space.id).map(\.id) == [contextID])
    #expect(try await cli.conversations(spaceID: space.id).map(\.id) == [conversationID])
}
