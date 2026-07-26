import Foundation
import AizenCore
import AizenStorage
import AizenTransport
import Testing
@testable import AizenHost
import AizenWire

@Test func hostUsesTheWireProtocol() {
    #expect(AizenHostModule.protocolGeneration == 1)
}

@Test func localHostReturnsTheStorageSnapshotThroughWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    _ = try await storage.transact { $0.spaces.append(.init(name: "Vivy")) }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))
    let response = try await transport.send(.init(messageID: "spaces", connectionSequence: 1, kind: .query, channel: .state, payload: .init(identifier: .init(rawValue: "aizen.query.space.list@1"), schemaVersion: 1, protobufBytes: Data(), stateAffecting: false)))
    let snapshot = try JSONDecoder().decode(StorageSnapshot.self, from: response.payload.protobufBytes)
    #expect(snapshot.spaces.map(\.name) == ["Vivy"])
}

@Test func runRegistryRejectsUnknownRuns() async {
    let registry = HostRunRegistry()
    await #expect(throws: HostRunRegistry.Error.self) {
        try await registry.updateLifecycle(.running, for: RunID())
    }
}
