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

@Test func clientReadsTypedConversationListsAndTimelines() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    let messages = [
        ConversationMessage(spaceID: space.id, sessionID: session.id, role: .user, content: "Hello"),
        ConversationMessage(spaceID: space.id, sessionID: session.id, role: .assistant, content: "Hi")
    ]
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
        $0.conversationMessages.append(contentsOf: messages)
    }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))

    #expect(try await client.conversations(spaceID: space.id) == [session])
    #expect(try await client.conversationTimeline(sessionID: session.id).map(\.content) == ["Hello", "Hi"])
}

@Test func clientReadsTypedRunsWithoutDecodingStorage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    let run = Run(spaceID: space.id, sessionID: session.id, lifecycle: .running)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
        $0.runs.append(run)
    }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))

    #expect(try await client.runs(spaceID: space.id) == [run])
}

@Test func clientReceivesSharedTransportRunEvents() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let publisher = RunEventPublisher()
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage, runEventPublisher: publisher)))
    let stream = try await client.runEvents()
    let run = Run(spaceID: SpaceID(), sessionID: SessionID())
    let eventTask = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await publisher.publish(for: run, kind: .assistantTextDelta("Hello"))
    let event = try #require(await eventTask.value)
    #expect(event.runID == run.id)
    #expect(event.kind == .assistantTextDelta("Hello"))
}

@Test func clientImportsAndRemovesLocalFolderResourcesThroughHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let spaceID = try await client.createSpace(name: "Vivy")

    let resourceID = try await client.importLocalFolder(spaceID: spaceID, path: folder.path)
    let resource = try #require(try await client.resources(spaceID: spaceID).first)
    #expect(resource.id == resourceID)
    #expect(resource.kind == .folder)
    #expect(resource.title == "folder")
    #expect(resource.details == .none)
    #expect(try await client.importLocalFolder(spaceID: spaceID, path: folder.path) == resourceID)
    #expect(try await client.resources(spaceID: spaceID).count == 1)
    let otherSpaceID = try await client.createSpace(name: "Other")
    await #expect(throws: HostProtocolError.duplicateResource(resourceID)) {
        try await client.importLocalFolder(spaceID: otherSpaceID, path: folder.path)
    }
    let contextID = try await client.createLocalFolderContext(spaceID: spaceID, resourceID: resourceID)
    let context = try #require(try await client.executionContexts(spaceID: spaceID, resourceID: resourceID).first)
    #expect(context.id == contextID)
    #expect(context.kind == .localFolder)
    #expect(context.hostReference == nil)
    let sessionID = try await client.createConversation(spaceID: spaceID, title: "Coding")
    try await client.attachExecutionContext(sessionID: sessionID, contextID: contextID)
    #expect(try await storage.load().sessions.first(where: { $0.id == sessionID })?.executionContextID == contextID)
    await #expect(throws: HostProtocolError.resourceInUse(resourceID)) {
        try await client.removeResource(id: resourceID)
    }
}

@Test func clientCancelsRunsThroughHostCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    let run = Run(spaceID: space.id, sessionID: session.id, lifecycle: .running)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
        $0.runs.append(run)
    }
    let runtime = CancelRecordingRuntime()
    let coordinator = ConversationRunCoordinator(storage: storage, runtime: runtime)
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage, conversationRuns: coordinator)))

    try await client.cancelRun(id: run.id)
    #expect(try await storage.load().runs.first?.lifecycle == .cancelled)
    #expect(await runtime.cancelledRunID == run.id)
}

@Test func clientSendsProjectlessConversationsThroughHostCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let runtime = ClientPromptRuntime()
    let coordinator = ConversationRunCoordinator(storage: storage, runtime: runtime)
    let sandboxes = ManagedSandboxService(storage: storage, rootURL: root.appendingPathComponent("sandboxes", isDirectory: true))
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage, conversationRuns: coordinator, managedSandboxes: sandboxes)))
    let spaceID = try await client.createSpace(name: "CLI")
    let sessionID = try await client.createConversation(spaceID: spaceID, title: "Untethered")
    let runID = RunID()
    #expect(try await client.sendConversation(
        spaceID: spaceID,
        sessionID: sessionID,
        content: "Hello",
        messageID: ConversationMessageID(),
        runID: runID
    ) == runID)
    #expect(try await storage.load().conversationMessages.map(\.content) == ["Hello"])
    #expect(try await storage.load().runs.first?.lifecycle == .succeeded)
}

private struct EchoHost: WireEndpoint {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope { envelope }
}

private actor ClientPromptRuntime: PromptRunRuntime {
    func start(run: Run) async throws {}
    func cancel(runID: RunID) async throws {}
    func send(message: String, to runID: RunID, onAssistantTextDelta: @escaping @Sendable (String) async -> Void) async throws -> String? { nil }
}

private actor CancelRecordingRuntime: PromptRunRuntime {
    private(set) var cancelledRunID: RunID?

    func start(run: Run) async throws {}
    func cancel(runID: RunID) async throws { cancelledRunID = runID }
    func send(message: String, to runID: RunID, onAssistantTextDelta: @escaping @Sendable (String) async -> Void) async throws -> String? { nil }
}
