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

@Test func journalSynchronizerPersistsOnlySuccessfullyReducedEvents() async throws {
    let store = RecordingJournalCursorStore()
    let synchronizer = JournalEventSynchronizer(cursorStore: store)
    let events = [journalEvent(cursor: 1), journalEvent(cursor: 2)]
    let response = ReadJournalEventsResponsePayload(events: events, oldestCursor: 1, latestCursor: 2, snapshotRequired: false)
    let applied = try await synchronizer.apply(response) { event in
        #expect(event.cursor < 3)
    }
    #expect(applied == 2)
    #expect(await store.cursor == 2)

    let duplicateApplied = try await synchronizer.apply(response) { _ in
        Issue.record("Duplicate events must not reach the reducer")
    }
    #expect(duplicateApplied == 2)

    await #expect(throws: ClientReducerFailure.expected) {
        try await synchronizer.apply(
            ReadJournalEventsResponsePayload(events: [journalEvent(cursor: 3)], oldestCursor: 1, latestCursor: 3, snapshotRequired: false)
        ) { _ in
            throw ClientReducerFailure.expected
        }
    }
    #expect(await store.cursor == 2)
}

@Test func journalSynchronizerRejectsGapsAndExpiredCursors() async throws {
    let store = RecordingJournalCursorStore()
    let synchronizer = JournalEventSynchronizer(cursorStore: store)
    await #expect(throws: JournalSynchronizationError.gap(expected: 1, received: 2)) {
        try await synchronizer.apply(
            ReadJournalEventsResponsePayload(events: [journalEvent(cursor: 2)], oldestCursor: 2, latestCursor: 2, snapshotRequired: false)
        ) { _ in }
    }
    await #expect(throws: JournalSynchronizationError.snapshotRequired) {
        try await synchronizer.apply(
            ReadJournalEventsResponsePayload(events: [], oldestCursor: 2, latestCursor: 2, snapshotRequired: true)
        ) { _ in }
    }
}

@Test func commandOutboxReplaysACommandAfterItsReceiptIsLost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact { $0.spaces.append(space) }
    let host = LocalHost(storage: storage)
    let outboxURL = root.appendingPathComponent("client-outbox.json")
    let outbox = FileCommandOutbox(url: outboxURL)
    let unreliableClient = HostClient(transport: ReceiptDroppingTransport(endpoint: host), commandOutbox: outbox)

    await #expect(throws: ReceiptDroppingTransport.Error.receiptLost) {
        _ = try await unreliableClient.importLocalFolder(spaceID: space.id, path: folder.path)
    }
    #expect(try await outbox.pendingCommands().count == 1)
    #expect(try await storage.load().resources.count == 1)

    let recoveredClient = HostClient(transport: InProcessTransport(endpoint: host), commandOutbox: FileCommandOutbox(url: outboxURL))
    #expect(try await recoveredClient.retryPendingCommands().count == 1)
    #expect(try await FileCommandOutbox(url: outboxURL).pendingCommands().isEmpty)
    #expect(try await storage.load().resources.count == 1)
}

@Test func routeFailoverReplaysTheSameCommandWithoutDuplicatingHostWork() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact { $0.spaces.append(space) }
    let host = LocalHost(storage: storage)
    let lan = try TransportRouteConfiguration(kind: .lan, endpoint: URL(string: "wss://aizen.local")!, expectedHostIdentity: "host")
    let tailscale = try TransportRouteConfiguration(kind: .tailscale, endpoint: URL(string: "wss://aizen.tailnet.ts.net")!, expectedHostIdentity: "host")
    let droppedReceipt = ReceiptDroppingTransport(endpoint: host)
    let recoveredRoute = RecordingTransport(endpoint: host)
    let router = TransportRouter(routes: [lan, tailscale]) { route in
        let transport: any WireTransport = route.id == lan.id ? droppedReceipt : recoveredRoute
        return .init(transport: transport, authenticatedHostIdentity: "host")
    }
    let outbox = FileCommandOutbox(url: root.appendingPathComponent("client-outbox.json"))
    let client = HostClient(transport: router, commandOutbox: outbox)

    await #expect(throws: ReceiptDroppingTransport.Error.receiptLost) {
        _ = try await client.importLocalFolder(spaceID: space.id, path: folder.path)
    }
    #expect(await router.activeRoute() == nil)
    #expect(try await outbox.pendingCommands().count == 1)

    _ = try await client.retryPendingCommands()

    #expect(await router.activeRoute()?.id == tailscale.id)
    #expect(try await storage.load().resources.count == 1)
    let droppedCommandIDs = await droppedReceipt.sentCommandIDs()
    let recoveredCommandIDs = await recoveredRoute.sentCommandIDs()
    #expect(droppedCommandIDs == recoveredCommandIDs)
    #expect(try await outbox.pendingCommands().isEmpty)
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
    #expect(await client.connectionState == .ready(protocolGeneration: 1))
}

@Test func clientNegotiatesProductAndProtocolCompatibilityBeforeCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: StorageRepository(url: root.appendingPathComponent("storage-v2.json")))))

    let capabilities = try await client.negotiate()

    #expect(capabilities.productVersion == "2.0.0")
    #expect(capabilities.minimumCompatibleProductVersion == "2.0.0")
    #expect(capabilities.minimumProtocolGeneration == 1)
    #expect(capabilities.maximumProtocolGeneration == 1)
    #expect(await client.connectionState == .ready(protocolGeneration: 1))
}

@Test func selectingSpaceIsAnExplicitProjectionTransition() {
    let first = Space(name: "Personal")
    let second = Space(name: "Work")
    let projection = SpaceProjection(spaces: [first, second]).selecting(second.id)
    #expect(projection.activeSpaceID == second.id)
    #expect(projection.spaces.map(\.name) == ["Personal", "Work"])
}

@Test func clientDecodesTypedHostProjectionSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    _ = try await storage.transact { $0.spaces.append(.init(name: "Vivy")) }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let response = try await client.projectionSnapshot()
    #expect(response.snapshot.spaces.map(\.name) == ["Vivy"])
}

@Test func clientListsSpacesWithoutDecodingStorage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    _ = try await storage.transact { $0.spaces.append(.init(name: "Vivy")) }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    #expect(try await client.spaces().map(\.name) == ["Vivy"])
}

@Test func clientListsContextFilesThroughTheHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let checkout = root.appendingPathComponent("checkout", isDirectory: true)
    try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
    try Data("readme".utf8).write(to: checkout.appendingPathComponent("README.md"))
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Files")
    let context = ExecutionContext(
        spaceID: space.id,
        kind: .repositoryCheckout,
        hostReference: .init(rawValue: "local-checkout:\(checkout.path)")
    )
    _ = try await storage.transact { snapshot in
        snapshot.spaces.append(space)
        snapshot.executionContexts.append(context)
    }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))

    #expect(try await client.contextFiles(executionContextID: context.id) == [
        .init(relativePath: "README.md", name: "README.md", isDirectory: false)
    ])
    #expect(try await client.contextTextFile(executionContextID: context.id, relativePath: "README.md") == "readme")
}

@Test func clientListsHostOwnedTerminalSessions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let otherSpace = Space(name: "Other")
    let terminal = TerminalSession(
        spaceID: space.id,
        title: "Server",
        tmuxSessionName: "aizen-vivy-server",
        paneID: "%1"
    )
    let otherTerminal = TerminalSession(
        spaceID: otherSpace.id,
        title: "Other",
        tmuxSessionName: "aizen-other",
        paneID: "%2"
    )
    _ = try await storage.transact {
        $0.spaces.append(contentsOf: [space, otherSpace])
        $0.terminalSessions.append(contentsOf: [terminal, otherTerminal])
    }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))

    let sessions = try await client.terminalSessions(spaceID: space.id)
    #expect(sessions.map(\.id) == [terminal.id])
    #expect(sessions.map(\.spaceID) == [space.id])
    #expect(sessions.map(\.tmuxSessionName) == ["aizen-vivy-server"])
}

@Test func clientCreatesTerminalSessionsThroughHostCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "Project", details: .hostPrivate(.init(rawValue: "local-folder:/tmp/project")))
    let context = ExecutionContext(spaceID: space.id, kind: .localFolder, resourceID: resource.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
    }
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage, terminalRuntime: ClientTerminalRuntime())))

    let session = try await client.createTerminalSession(spaceID: space.id, executionContextID: context.id, title: "Server")
    #expect(session.spaceID == space.id)
    #expect(session.executionContextID == context.id)
    #expect(session.tmuxSessionName == "aizen-client")
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

@Test func recreatingAClientDoesNotTerminateHostOwnedRuns() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Persistent")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Long-running")
    let run = Run(spaceID: space.id, sessionID: session.id, lifecycle: .running)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
        $0.runs.append(run)
    }
    let host = LocalHost(storage: storage)

    var firstClient: HostClient? = HostClient(transport: InProcessTransport(endpoint: host))
    #expect(try await firstClient?.runs(spaceID: space.id) == [run])
    await firstClient?.disconnect()
    firstClient = nil

    let recreatedClient = HostClient(transport: InProcessTransport(endpoint: host))
    #expect(try await recreatedClient.runs(spaceID: space.id) == [run])
    #expect(try await storage.load().runs.first?.lifecycle == .running)
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
    #expect(resource.details == .hostPrivate(.init(rawValue: "local-folder:\(folder.resolvingSymlinksInPath().path)")))
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
    let disposableFolder = root.appendingPathComponent("disposable", isDirectory: true)
    try FileManager.default.createDirectory(at: disposableFolder, withIntermediateDirectories: true)
    let disposableResourceID = try await client.importLocalFolder(spaceID: spaceID, path: disposableFolder.path)
    let disposableContextID = try await client.createLocalFolderContext(spaceID: spaceID, resourceID: disposableResourceID)
    try await client.removeExecutionContext(id: disposableContextID)
    #expect(try await client.executionContexts(spaceID: spaceID, resourceID: disposableResourceID).isEmpty)
    let sessionID = try await client.createConversation(spaceID: spaceID, title: "Coding")
    try await client.attachExecutionContext(sessionID: sessionID, contextID: contextID)
    #expect(try await storage.load().sessions.first(where: { $0.id == sessionID })?.executionContextID == contextID)
    await #expect(throws: HostProtocolError.executionContextInUse(contextID)) {
        try await client.removeExecutionContext(id: contextID)
    }
    await #expect(throws: HostProtocolError.resourceInUse(resourceID)) {
        try await client.removeResource(id: resourceID)
    }
    try await client.detachExecutionContext(sessionID: sessionID)
    #expect(try await storage.load().sessions.first(where: { $0.id == sessionID })?.executionContextID == nil)
    try await client.removeExecutionContext(id: contextID)
    try await client.removeResource(id: resourceID)
}

@Test func clientImportsRepositoryResourcesAndCheckoutContextsThroughHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    git.arguments = ["init", repository.path]
    try git.run()
    git.waitUntilExit()
    #expect(git.terminationStatus == 0)

    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let spaceID = try await client.createSpace(name: "Vivy")
    let resourceID = try await client.importLocalRepository(spaceID: spaceID, path: repository.path)
    let resource = try #require(try await client.resources(spaceID: spaceID).first)
    #expect(resource.id == resourceID)
    #expect(resource.kind == .repository)
    #expect(resource.details == .hostPrivate(.init(rawValue: "local-repository:\(repository.resolvingSymlinksInPath().path)")))
    #expect(try await client.refreshRepositoryResource(id: resourceID) == .init(
        resourceID: resourceID.description,
        availability: .available,
        branch: "main"
    ))
    let contextID = try await client.createRepositoryCheckoutContext(spaceID: spaceID, resourceID: resourceID)
    let context = try #require(try await client.executionContexts(spaceID: spaceID, resourceID: resourceID).first)
    #expect(context.id == contextID)
    #expect(context.kind == .repositoryCheckout)
    #expect(context.hostReference == nil)
}

@Test func clientReadsStructuredRepositoryStatusThroughHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Git")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let reader = ClientRepositoryStatusReader()
    let updater = ClientRepositoryIndexUpdater()
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage, repositoryStatusReader: reader, repositoryDiffReader: ClientRepositoryDiffReader(), repositoryBranchReader: ClientRepositoryBranchReader(), repositoryIndexUpdater: updater, repositoryCommitter: ClientRepositoryCommitter(), repositoryBranchUpdater: ClientRepositoryBranchUpdater(), repositoryFetcher: ClientRepositoryFetcher(), repositoryPuller: ClientRepositoryPuller(), repositoryPusher: ClientRepositoryPusher())))

    #expect(try await client.repositoryStatus(id: resource.id, maximumEntries: 1) == .init(
        resourceID: resource.id.description,
        repositoryRevision: "revision",
        indexRevision: "index",
        entries: [.init(path: "README.md", indexStatus: "?", worktreeStatus: "?")],
        truncated: false
    ))
    #expect(try await client.repositoryDiff(id: resource.id, relativePath: "README.md", maximumBytes: 64) == .init(resourceID: resource.id.description, repositoryRevision: "revision", indexRevision: "index", unifiedDiff: Data("diff".utf8), truncated: false))
    #expect(try await client.repositoryBranches(id: resource.id, maximumBranches: 1) == .init(resourceID: resource.id.description, repositoryRevision: "revision", indexRevision: "index", branches: [.init(name: "main", revision: "abc", isCurrent: true)], truncated: false))
    let update = try await client.updateRepositoryIndex(
        id: resource.id,
        relativePaths: ["README.md"],
        expectedIndexRevision: String(repeating: "a", count: 64),
        stage: true
    )
    #expect(update.indexRevision == String(repeating: "b", count: 64))
    #expect(UUID(uuidString: update.operationID) != nil)
    #expect(await updater.requestedPaths == ["README.md"])
    let commit = try await client.commitRepository(id: resource.id, message: "Ship it", expectedRepositoryRevision: "revision", expectedIndexRevision: String(repeating: "a", count: 64))
    #expect(commit.repositoryRevision == String(repeating: "c", count: 40))
    #expect(UUID(uuidString: commit.operationID) != nil)
    let branch = try await client.updateRepositoryBranch(id: resource.id, branchName: "feature/reignition", expectedRepositoryRevision: "revision", expectedIndexRevision: String(repeating: "a", count: 64), create: true)
    #expect(branch.repositoryRevision == String(repeating: "c", count: 40))
    #expect(UUID(uuidString: branch.operationID) != nil)
    let fetched = try await client.fetchRepository(id: resource.id, expectedRepositoryRevision: "revision", expectedIndexRevision: String(repeating: "a", count: 64))
    #expect(fetched.repositoryRevision == String(repeating: "c", count: 40))
    #expect(UUID(uuidString: fetched.operationID) != nil)
    let pulled = try await client.pullRepository(id: resource.id, expectedRepositoryRevision: "revision", expectedIndexRevision: String(repeating: "a", count: 64))
    #expect(pulled.repositoryRevision == String(repeating: "c", count: 40))
    #expect(UUID(uuidString: pulled.operationID) != nil)
    let pushed = try await client.pushRepository(id: resource.id, expectedRepositoryRevision: "revision", expectedIndexRevision: String(repeating: "a", count: 64))
    #expect(pushed.repositoryRevision == String(repeating: "c", count: 40))
    #expect(UUID(uuidString: pushed.operationID) != nil)
}

@Test func clientImportsWebResourcesThroughHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let client = HostClient(transport: InProcessTransport(endpoint: LocalHost(storage: storage)))
    let spaceID = try await client.createSpace(name: "Vivy")
    let url = try #require(URL(string: "https://example.com/docs"))

    let resourceID = try await client.importWebResource(spaceID: spaceID, url: url, title: "Docs")
    let resource = try #require(try await client.resources(spaceID: spaceID).first)
    #expect(resource.id == resourceID)
    #expect(resource.kind == .webSource)
    #expect(resource.title == "Docs")
    #expect(resource.details == .web(.init(url: url)))
    #expect(try await client.importWebResource(spaceID: spaceID, url: url, title: "Ignored") == resourceID)
    #expect(try await client.resources(spaceID: spaceID).count == 1)
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

@Test func clientCancelsXcodeBuildOperationsThroughHostCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Xcode")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "folder", details: .hostPrivate(.init(rawValue: "local-folder:\(folder.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let builder = ClientCancellableXcodeBuilder()
    let host = LocalHost(storage: storage, xcodeProjectInspector: ClientXcodeProjectInspector(), xcodeProjectBuilder: builder)
    let client = HostClient(transport: InProcessTransport(endpoint: host))
    let operationID = try await client.buildXcodeProject(resourceID: resource.id, projectID: "App.xcodeproj", scheme: "App")
    try await client.cancelOperation(id: operationID)
    #expect(await builder.didCancel)
    #expect(try await storage.load().operations.first?.lifecycle == .cancelled)
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

@Test func clientSurfacesTypedHostFailures() async throws {
    let client = HostClient(transport: InProcessTransport(endpoint: FailingHost()))
    await #expect(throws: HostClient.Error.hostFailure(code: "invalid-resource", message: "Resource is unavailable")) {
        _ = try await client.spaces()
    }
}

private struct EchoHost: WireEndpoint {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope { envelope }
}

private struct FailingHost: WireEndpoint {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        try .init(messageID: envelope.messageID, connectionSequence: envelope.connectionSequence, kind: .error, channel: .control, payload: .init(HostErrorPayload(code: "invalid-resource", message: "Resource is unavailable")))
    }
}

private actor ReceiptDroppingTransport: WireTransport {
    enum Error: Swift.Error, Sendable, Equatable {
        case receiptLost
    }

    private let endpoint: any WireEndpoint
    private var commandIDs: [String] = []

    init(endpoint: any WireEndpoint) {
        self.endpoint = endpoint
    }

    func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        if envelope.kind == .command { commandIDs.append(envelope.messageID) }
        _ = try await endpoint.receive(envelope)
        throw Error.receiptLost
    }

    func sentCommandIDs() -> [String] { commandIDs }
}

private actor RecordingTransport: WireTransport {
    private let endpoint: any WireEndpoint
    private var commandIDs: [String] = []

    init(endpoint: any WireEndpoint) {
        self.endpoint = endpoint
    }

    func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        if envelope.kind == .command { commandIDs.append(envelope.messageID) }
        return try await endpoint.receive(envelope)
    }

    func sentCommandIDs() -> [String] { commandIDs }
}

private actor RecordingJournalCursorStore: JournalCursorStore {
    private(set) var cursor: UInt64 = 0

    func loadCursor() -> UInt64 { cursor }
    func saveCursor(_ cursor: UInt64) { self.cursor = cursor }
}

private actor ClientTerminalRuntime: TerminalRuntime {
    func createTerminal(
        id: SessionID,
        spaceID: SpaceID,
        executionContext: ExecutionContext,
        resource: Resource?,
        title: String?,
        initialCommand: String?
    ) async throws -> TerminalLaunch {
        TerminalLaunch(tmuxSessionName: "aizen-client", paneID: "%1")
    }
}

private struct ClientXcodeProjectInspector: XcodeProjectInspecting {
    func schemes(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) async throws -> [String] { ["App"] }
}

private actor ClientCancellableXcodeBuilder: XcodeProjectBuilding, XcodeBuildRunning {
    private(set) var didCancel = false

    func startXcodeProjectBuild(at url: URL, kind: XcodeProjectDescriptor.Kind, scheme: String, destination: String) async throws -> any XcodeBuildRunning { self }
    func waitForCompletion() async throws {
        while !didCancel {
            try await Task.sleep(for: .seconds(1))
        }
        throw CancellationError()
    }
    func cancel() { didCancel = true }
}

private actor ClientRepositoryStatusReader: RepositoryStatusReading {
    func status(at repositoryURL: URL, maximumEntries: Int) async throws -> RepositoryStatusSnapshot {
        .init(
            repositoryRevision: "revision",
            indexRevision: "index",
            entries: [.init(path: "README.md", indexStatus: "?", worktreeStatus: "?")],
            truncated: false
        )
    }
}

private actor ClientRepositoryDiffReader: RepositoryDiffReading {
    func diff(at repositoryURL: URL, relativePath: String, maximumBytes: Int) async throws -> RepositoryDiffSnapshot {
        .init(repositoryRevision: "revision", indexRevision: "index", unifiedDiff: Data("diff".utf8), truncated: false)
    }
}

private actor ClientRepositoryBranchReader: RepositoryBranchReading {
    func branches(at repositoryURL: URL, maximumBranches: Int) async throws -> RepositoryBranchesSnapshot {
        .init(repositoryRevision: "revision", indexRevision: "index", branches: [.init(name: "main", revision: "abc", isCurrent: true)], truncated: false)
    }
}

private actor ClientRepositoryIndexUpdater: RepositoryIndexUpdating {
    private(set) var requestedPaths: [String] = []

    func updateIndex(at repositoryURL: URL, relativePaths: [String], expectedIndexRevision: String, stage: Bool) async throws -> String {
        requestedPaths = relativePaths
        return String(repeating: "b", count: 64)
    }
}

private actor ClientRepositoryCommitter: RepositoryCommitting {
    func commit(at repositoryURL: URL, message: String, expectedRepositoryRevision: String, expectedIndexRevision: String, amend: Bool) async throws -> RepositoryCommitResult {
        .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor ClientRepositoryBranchUpdater: RepositoryBranchUpdating {
    func updateBranch(at repositoryURL: URL, branchName: String, expectedRepositoryRevision: String, expectedIndexRevision: String, create: Bool) async throws -> RepositoryBranchUpdateResult {
        .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor ClientRepositoryFetcher: RepositoryFetching {
    func fetch(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult {
        .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor ClientRepositoryPuller: RepositoryPulling {
    func pull(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult {
        .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor ClientRepositoryPusher: RepositoryPushing {
    func push(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult {
        .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private enum ClientReducerFailure: Error, Equatable {
    case expected
}

private func journalEvent(cursor: UInt64) -> JournalEvent {
    JournalEvent(
        cursor: cursor,
        aggregateID: "host",
        aggregateType: "host",
        aggregateRevision: cursor,
        payloadIdentifier: "aizen.event.host@1",
        payloadSchemaVersion: 1,
        payloadBytes: Data([UInt8(cursor)]),
        durability: .durable
    )
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
