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

@Test func localHostListsSpacesThroughTypedWirePayloads() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    _ = try await storage.transact { $0.spaces.append(.init(name: "Vivy", icon: "sparkles")) }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))
    let response = try await transport.send(.init(
        messageID: "list-spaces",
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ListSpacesQueryPayload())
    ))
    #expect(try ListSpacesResponsePayload(protobufBytes: response.payload.protobufBytes).spaces.map(\.name) == ["Vivy"])
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

@Test func runEventsAreOrderedAndScopedToTheHostRun() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Host")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Run")
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
    }
    let publisher = RunEventPublisher()
    let stream = await publisher.events()
    let collector = Task { () -> [RunEvent] in
        var iterator = stream.makeAsyncIterator()
        var events: [RunEvent] = []
        while events.count < 5, let event = await iterator.next() {
            events.append(event)
        }
        return events
    }
    let coordinator = RunCoordinator(storage: storage, runtime: RecordingRuntime(), eventPublisher: publisher)
    let run = Run(spaceID: space.id, sessionID: session.id)
    try await coordinator.start(run)
    try await coordinator.cancel(run.id)
    let events = await collector.value

    #expect(events.map(\.sequence) == [1, 2, 3, 4, 5])
    #expect(events.allSatisfy { $0.spaceID == space.id && $0.sessionID == session.id && $0.runID == run.id })
    #expect(events.map(\.kind) == [.lifecycle(.preparingContext), .lifecycle(.startingAgent), .lifecycle(.running), .lifecycle(.cancelling), .lifecycle(.cancelled)])
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

@Test func hostRenamesAndDeletesEmptySpacesThroughTypedCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact { $0.spaces.append(space) }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))

    _ = try await transport.send(.init(
        messageID: "rename-space",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(RenameSpaceCommandPayload(spaceID: space.id.description, name: "Aizen"))
    ))
    #expect(try await storage.load().spaces.map(\.name) == ["Aizen"])

    _ = try await transport.send(.init(
        messageID: "delete-space",
        connectionSequence: 2,
        kind: .command,
        channel: .state,
        payload: try .init(DeleteSpaceCommandPayload(spaceID: space.id.description))
    ))
    #expect(try await storage.load().spaces.isEmpty)
}

@Test func hostRejectsDeletingSpacesThatOwnData() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(Session(spaceID: space.id, kind: .conversation, title: "Plan"))
    }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))
    await #expect(throws: HostProtocolError.spaceNotEmpty(space.id)) {
        _ = try await transport.send(.init(
            messageID: "delete-space",
            connectionSequence: 1,
            kind: .command,
            channel: .state,
            payload: try .init(DeleteSpaceCommandPayload(spaceID: space.id.description))
        ))
    }
}

@Test func hostCreatesProjectlessConversationsThroughTypedCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact { $0.spaces.append(space) }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))
    let response = try await transport.send(.init(
        messageID: "create-conversation",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(CreateConversationCommandPayload(spaceID: space.id.description, title: "Plan"))
    ))
    let result = try CreateConversationResultPayload(protobufBytes: response.payload.protobufBytes)
    let snapshot = try await storage.load()
    #expect(UUID(uuidString: result.sessionID) != nil)
    #expect(snapshot.sessions == [Session(id: SessionID(rawValue: UUID(uuidString: result.sessionID)!), spaceID: space.id, kind: .conversation, title: "Plan")])
}

@Test func hostSendsConversationThroughTheConfiguredRuntime() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
    }
    let runtime = PromptRecordingRuntime()
    let coordinator = ConversationRunCoordinator(storage: storage, runtime: runtime)
    let sandboxes = ManagedSandboxService(storage: storage, rootURL: root.appendingPathComponent("sandboxes", isDirectory: true))
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage, conversationRuns: coordinator, managedSandboxes: sandboxes))
    let runID = RunID()
    let response = try await transport.send(.init(
        messageID: "send-conversation",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(SendConversationCommandPayload(
            spaceID: space.id.description,
            sessionID: session.id.description,
            messageID: ConversationMessageID().description,
            runID: runID.description,
            content: "Make a plan"
        ))
    ))
    #expect(try SendConversationResultPayload(protobufBytes: response.payload.protobufBytes).runID == runID.description)
    let snapshot = try await storage.load()
    #expect(snapshot.runs.first?.lifecycle == .succeeded)
    #expect(snapshot.runs.first?.executionContextID == snapshot.sessions.first?.executionContextID)
    #expect(snapshot.executionContexts.first?.kind == .managedTemporarySandbox)
    #expect((await runtime.prompted).first?.1 == "Make a plan")
}

@Test func managedSandboxProvisioningLinksAProjectlessConversation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
    }
    let sandboxes = ManagedSandboxService(storage: storage, rootURL: root.appendingPathComponent("sandboxes", isDirectory: true))
    let context = try await sandboxes.provision(for: session.id, persistence: .temporary)
    let snapshot = try await storage.load()
    let directory = await sandboxes.directoryURL(for: context)
    let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber

    #expect(context.spaceID == space.id)
    #expect(context.kind == .managedTemporarySandbox)
    #expect(snapshot.sessions.first?.executionContextID == context.id)
    #expect(snapshot.executionContexts == [context])
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("metadata.json").path))
    #expect(permissions?.intValue == 0o700)
}

@Test func conversationRunCoordinatorPersistsThenPromptsExactlyOneRun() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
    }
    let runtime = PromptRecordingRuntime()
    let coordinator = ConversationRunCoordinator(storage: storage, runtime: runtime)
    let run = Run(spaceID: space.id, sessionID: session.id)
    let message = ConversationMessage(spaceID: space.id, sessionID: session.id, role: .user, content: "Make a plan")

    try await coordinator.submit(message: message, run: run)

    let snapshot = try await storage.load()
    #expect(snapshot.conversationMessages == [message])
    #expect(snapshot.runs.first?.id == run.id)
    #expect(snapshot.runs.first?.lifecycle == .succeeded)
    let prompted = await runtime.prompted
    #expect(prompted.count == 1)
    #expect(prompted.first?.0 == run.id)
    #expect(prompted.first?.1 == "Make a plan")
}

@Test func conversationRunCoordinatorPersistsAssistantOutputWithItsRun() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
    }
    let runtime = PromptRecordingRuntime(assistantReply: "Here is the plan.")
    let publisher = RunEventPublisher()
    let stream = await publisher.events()
    let collector = Task { () -> [RunEvent] in
        var iterator = stream.makeAsyncIterator()
        var events: [RunEvent] = []
        while events.count < 5, let event = await iterator.next() {
            events.append(event)
        }
        return events
    }
    let coordinator = ConversationRunCoordinator(storage: storage, runtime: runtime, eventPublisher: publisher)
    let run = Run(spaceID: space.id, sessionID: session.id)
    let message = ConversationMessage(spaceID: space.id, sessionID: session.id, role: .user, content: "Make a plan")

    try await coordinator.submit(message: message, run: run)

    let messages = try await storage.load().conversationMessages
    #expect(messages.map(\.role) == [.user, .assistant])
    #expect(messages.map(\.content) == ["Make a plan", "Here is the plan."])
    #expect(messages.last?.runID == run.id)
    #expect((await collector.value).map(\.kind) == [
        .lifecycle(.preparingContext), .lifecycle(.startingAgent), .lifecycle(.running), .assistantTextDelta("Here is the plan."), .lifecycle(.succeeded)
    ])
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

private actor PromptRecordingRuntime: PromptRunRuntime {
    private(set) var prompted: [(RunID, String)] = []
    private let assistantReply: String?

    init(assistantReply: String? = nil) {
        self.assistantReply = assistantReply
    }

    func start(run: Run) async throws {}
    func cancel(runID: RunID) async throws {}
    func send(
        message: String,
        to runID: RunID,
        onAssistantTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String? {
        prompted.append((runID, message))
        if let assistantReply { await onAssistantTextDelta(assistantReply) }
        return assistantReply
    }
}
