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
    let response = try await transport.send(.init(messageID: "spaces", connectionSequence: 1, kind: .query, channel: .state, payload: try .init(SnapshotRequestPayload())))
    let wireSnapshot = try SnapshotResponsePayload(protobufBytes: response.payload.protobufBytes)
    let snapshot = try JSONDecoder().decode(StorageSnapshot.self, from: wireSnapshot.snapshot)
    #expect(snapshot.spaces.map(\.name) == ["Vivy"])
}

@Test func coordinatorOwnsRunLifecycle() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Host")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Run")
    _ = try await storage.transact { snapshot in
        snapshot.spaces.append(space)
        snapshot.sessions.append(session)
    }
    let coordinator = RunCoordinator(storage: storage, runtime: RecordingRuntime())
    let run = Run(spaceID: space.id, sessionID: session.id)
    try await coordinator.start(run)
    #expect(try await coordinator.run(for: run.id)?.lifecycle == .running)
    try await coordinator.cancel(run.id)
    #expect(try await coordinator.run(for: run.id)?.lifecycle == .cancelled)
}

@Test func hostCreatesSpacesThroughTypedCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))
    let response = try await transport.send(.init(
        messageID: "create-space",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(CreateSpaceCommandPayload(name: "Vivy", icon: "sparkles"))
    ))
    let result = try CreateSpaceResultPayload(protobufBytes: response.payload.protobufBytes)
    #expect(UUID(uuidString: result.spaceID) != nil)
    #expect(try await storage.load().spaces.map(\.name) == ["Vivy"])
}

@Test func coordinatorRejectsUnknownRunWithoutTouchingRuntime() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let coordinator = RunCoordinator(storage: StorageRepository(url: root.appendingPathComponent("storage-v2.json")), runtime: RecordingRuntime())
    let runID = RunID()
    await #expect(throws: RunCoordinator.Error.unknownRun(runID)) {
        try await coordinator.cancel(runID)
    }
}

private actor RecordingRuntime: RunRuntime {
    func start(run: Run) async throws {}
    func cancel(runID: RunID) async throws {}
}
