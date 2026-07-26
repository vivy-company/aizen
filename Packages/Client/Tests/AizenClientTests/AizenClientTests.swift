import Foundation
import AizenCore
import AizenHost
import AizenStorage
import AizenTransport
import Testing
@testable import AizenClient
import AizenWire

@Test func clientUsesTheWireProtocol() {
    #expect(AizenClientModule.protocolGeneration == 1)
}

@Test func clientNegotiatesThroughTheProtobufInProcessTransport() async throws {
    let client = HostClient(transport: InProcessTransport(endpoint: EchoHost()))
    let response = try await client.send(.init(
        messageID: "hello",
        connectionSequence: 1,
        kind: .hello,
        channel: .control,
        payload: .init(identifier: .init(rawValue: "aizen.control.hello@1"), schemaVersion: 1, protobufBytes: Data(), stateAffecting: false)
    ))
    #expect(response.messageID == "hello")
    #expect(await client.connectionState == .connected(protocolGeneration: 1))
}

@Test func selectingSpaceIsAnExplicitProjectionTransition() {
    let first = Space(name: "Personal")
    let second = Space(name: "Work")
    let projection = SpaceProjection(spaces: [first, second]).selecting(second.id)
    #expect(projection.activeSpaceID == second.id)
    #expect(projection.spaces.map(\.name) == ["Personal", "Work"])
}

@Test func clientDecodesTypedHostSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    _ = try await storage.transact { $0.spaces.append(.init(name: "Vivy")) }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let response = try await client.snapshot()
    let snapshot = try JSONDecoder().decode(StorageSnapshot.self, from: response.snapshot)
    #expect(snapshot.spaces.map(\.name) == ["Vivy"])
}

@Test func clientListsSpacesWithoutDecodingStorage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    _ = try await storage.transact { $0.spaces.append(.init(name: "Vivy")) }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    #expect(try await client.spaces().map(\.name) == ["Vivy"])
}

@Test func clientCreatesSpacesThroughHostCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let id = try await client.createSpace(name: "CLI")
    #expect(try await storage.load().spaces == [Space(id: id, name: "CLI")])
}

@Test func clientRenamesAndDeletesSpacesThroughHostCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let id = try await client.createSpace(name: "CLI")
    try await client.renameSpace(id: id, name: "Aizen")
    #expect(try await client.spaces().map(\.name) == ["Aizen"])
    try await client.deleteSpace(id: id)
    #expect(try await client.spaces().isEmpty)
}

@Test func clientCreatesProjectlessConversationsThroughHostCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let spaceID = try await client.createSpace(name: "CLI")
    let sessionID = try await client.createConversation(spaceID: spaceID, title: "Untethered")
    #expect(try await storage.load().sessions == [Session(id: sessionID, spaceID: spaceID, kind: .conversation, title: "Untethered")])
}

private struct EchoHost: WireEndpoint {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope { envelope }
}
