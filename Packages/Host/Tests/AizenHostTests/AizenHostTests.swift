import Foundation
import AizenCore
import AizenStorage
import AizenSecurity
import AizenTransport
import Testing
@testable import AizenHost
import AizenWire

@Test func hostUsesTheWireProtocol() {
    #expect(AizenHostModule.protocolGeneration == 1)
}

@Test func deviceAuthorizationGateDeniesUnpairedAndRevokedDevices() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let gate = DeviceAuthorizationGate(storage: storage)
    let deviceID = DeviceID()

    await #expect(throws: DeviceAuthorizationError.deviceNotPaired) {
        try await gate.require(deviceID: deviceID, capability: .spaceRead, route: "lan")
    }
    #expect(try await storage.load().securityAuditRecords.map(\.kind) == [.authorizationDenied])

    let device = DevicePublicIdentity(deviceID: deviceID, displayName: "Phone", platform: "iOS", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    try await storage.saveDeviceAuthorization(DeviceAuthorization(device: device, grants: [CapabilityGrant(capability: .spaceRead)]))
    try await gate.require(deviceID: deviceID, capability: .spaceRead, route: "lan")
    await #expect(throws: DeviceAuthorizationError.capabilityDenied(.fileWrite)) {
        try await gate.require(deviceID: deviceID, capability: .fileWrite, route: "lan")
    }
}

@Test func pairingApprovalRequiresAValidSingleUseInvitation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let hostIdentity = LocalCryptographicIdentity()
    let invitation = try PairingInvitation(
        secret: Data(repeating: 9, count: 32),
        host: HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity()),
        endpointHints: ["wss://aizen.local"],
        expiresAt: Date().addingTimeInterval(60)
    )
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    let service = PairingApprovalService(storage: storage)
    try await service.issue(invitation)

    let authorization = try await service.approve(device: device, tokenID: invitation.tokenID, secret: invitation.secret, grants: [.init(capability: .spaceRead)], route: "lan")
    #expect(authorization.permits(.spaceRead))
    #expect(try await storage.deviceAuthorization(for: device.deviceID) == authorization)
    await #expect(throws: SecurityError.pairingTokenUnknown) {
        try await service.approve(device: device, tokenID: invitation.tokenID, secret: invitation.secret, grants: [], route: "lan")
    }
}

@Test func pairingRequestsRequireLocalApprovalAndNeverExposeTheSecret() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let secret = Data(repeating: 7, count: 32)
    let invitation = try PairingInvitation(secret: secret, host: host, endpointHints: [], expiresAt: Date().addingTimeInterval(60))
    let approval = PairingApprovalService(storage: storage)
    try await approval.issue(invitation)
    let deviceIdentity = LocalCryptographicIdentity()
    let request = PairingRequestPayload(tokenID: invitation.tokenID, pairingSecret: secret, hostID: host.hostID, deviceID: DeviceID(), deviceDisplayName: "Phone", devicePlatform: "iOS", deviceSigningPublicKey: deviceIdentity.publicIdentity().signingPublicKey, deviceKeyAgreementPublicKey: deviceIdentity.publicIdentity().keyAgreementPublicKey, route: "lan")
    let registry = PairingRequestRegistry(hostID: host.hostID, approval: approval)

    let pending = try await registry.submit(request)
    #expect(pending.device.displayName == "Phone")
    #expect(try await storage.deviceAuthorizations().isEmpty)
    let authorization = try await registry.approve(tokenID: pending.tokenID, grants: [.init(capability: .spaceRead)])
    #expect(authorization.device.deviceID == request.deviceID)
    #expect(try await storage.deviceAuthorization(for: request.deviceID) == authorization)
    await #expect(throws: PairingRequestError.unknownRequest) {
        try await registry.approve(tokenID: pending.tokenID, grants: [])
    }
}

@Test func remoteSessionAuthenticationAcceptsOnlyPersistedUnrevokedDeviceIdentity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let deviceIdentity = LocalCryptographicIdentity()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: deviceIdentity.publicIdentity())
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [.init(capability: .spaceRead)]))
    let clientEphemeral = ConnectionEphemeralKey()
    let start = AuthenticationStartPayload(
        hostID: host.hostID,
        deviceID: device.deviceID,
        connectionID: UUID(),
        clientNonce: Data(repeating: 1, count: 32),
        deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
        deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
        clientEphemeralPublicKey: clientEphemeral.publicKey,
        route: "lan"
    )
    let authenticator = RemoteSessionAuthenticator(host: host, hostIdentity: hostIdentity, storage: storage)
    let source = RemoteRequestSource("192.168.1.20")
    let challenge = try await authenticator.begin(start, source: source)
    await #expect(throws: RemoteSessionAuthenticationError.rejected) {
        try await authenticator.begin(start, source: source)
    }
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: 1,
        hostID: challenge.hostID,
        deviceID: challenge.deviceID,
        connectionID: challenge.connectionID,
        clientNonce: challenge.clientNonce,
        serverNonce: challenge.serverNonce,
        clientEphemeralPublicKey: start.clientEphemeralPublicKey,
        serverEphemeralPublicKey: challenge.serverEphemeralPublicKey,
        route: .lan
    )
    let hostPublicIdentity = try PublicCryptographicIdentity(signingPublicKey: challenge.hostSigningPublicKey, keyAgreementPublicKey: challenge.hostKeyAgreementPublicKey, createdAt: host.cryptographicIdentity.createdAt)
    try ConnectionAuthenticator.verify(.init(participant: .host, signature: challenge.hostSignature), expectedParticipant: .host, identity: hostPublicIdentity, binding: binding)
    let deviceProof = ConnectionAuthenticator.makeProof(participant: .device, identity: deviceIdentity, binding: binding)
    let session = try await authenticator.finish(.init(connectionID: start.connectionID, deviceSignature: deviceProof.signature))
    #expect(session.deviceID == device.deviceID)
    #expect(session.route == .lan)

    let unpaired = AuthenticationStartPayload(
        hostID: host.hostID,
        deviceID: DeviceID(),
        connectionID: UUID(),
        clientNonce: Data(repeating: 2, count: 32),
        deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
        deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
        clientEphemeralPublicKey: ConnectionEphemeralKey().publicKey,
        route: "lan"
    )
    await #expect(throws: RemoteSessionAuthenticationError.rejected) {
        try await authenticator.begin(unpaired, source: source)
    }

    var revoked = DeviceAuthorization(device: device, grants: [.init(capability: .spaceRead)])
    revoked.revokedAt = Date()
    try await storage.saveDeviceAuthorization(revoked)
    let reconnect = AuthenticationStartPayload(
        hostID: host.hostID,
        deviceID: device.deviceID,
        connectionID: UUID(),
        clientNonce: Data(repeating: 3, count: 32),
        deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
        deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
        clientEphemeralPublicKey: ConnectionEphemeralKey().publicKey,
        route: "lan"
    )
    await #expect(throws: RemoteSessionAuthenticationError.rejected) {
        try await authenticator.begin(reconnect, source: source)
    }
}

@Test func remoteRequestRateLimiterBoundsBurstAndRefillsWithoutUnboundedSources() async throws {
    let limit = RemoteRequestRateLimit(burst: 2, refillWindow: 10)
    let limits = Dictionary(uniqueKeysWithValues: RemoteRequestKind.allCases.map { ($0, limit) })
    let limiter = RemoteRequestRateLimiter(limits: limits, maximumTrackedBuckets: 1)
    let source = RemoteRequestSource("192.168.1.20")
    let start = Date(timeIntervalSince1970: 1_000)

    try await limiter.require(kind: .authentication, source: source, now: start)
    try await limiter.require(kind: .authentication, source: source, now: start)
    await #expect(throws: RemoteRequestRateLimitError.limited(.authentication)) {
        try await limiter.require(kind: .authentication, source: source, now: start)
    }
    try await limiter.require(kind: .authentication, source: source, now: start.addingTimeInterval(5))
    await #expect(throws: RemoteRequestRateLimitError.limited(.snapshot)) {
        try await limiter.require(kind: .snapshot, source: RemoteRequestSource("192.168.1.21"), now: start)
    }
}

@Test func remoteHostEndpointEnforcesAuthorizationBeforeDispatchingWireRequests() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Private")
    _ = try await storage.transact { $0.spaces.append(space) }
    let allowedDevice = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    try await storage.saveDeviceAuthorization(.init(device: allowedDevice, grants: [.init(capability: .hostRead)]))
    let endpoint = LocalHost(storage: storage)
    let gate = DeviceAuthorizationGate(storage: storage)
    let source = RemoteRequestSource("192.168.1.20")
    let allowed = RemoteHostEndpoint(
        endpoint: endpoint,
        storage: storage,
        authorization: gate,
        rateLimiter: RemoteRequestRateLimiter(),
        session: try authenticatedSession(for: allowedDevice.deviceID),
        source: source
    )
    let listSpaces = ProtocolEnvelope(messageID: "remote-list", connectionSequence: 1, kind: .query, channel: .state, payload: try .init(ListSpacesQueryPayload()))
    let response = try await allowed.receive(listSpaces)
    #expect(try ListSpacesResponsePayload(protobufBytes: response.payload.protobufBytes).spaces.map(\.name) == ["Private"])

    let unpaired = RemoteHostEndpoint(
        endpoint: endpoint,
        storage: storage,
        authorization: gate,
        rateLimiter: RemoteRequestRateLimiter(),
        session: try authenticatedSession(for: DeviceID()),
        source: source
    )
    await #expect(throws: DeviceAuthorizationError.deviceNotPaired) {
        try await unpaired.receive(listSpaces)
    }

    let unsupported = ProtocolEnvelope(messageID: "remote-unsupported", connectionSequence: 2, kind: .command, channel: .state, payload: try .init(CreateSpaceResultPayload(spaceID: SpaceID().description)))
    await #expect(throws: RemoteHostAuthorizationError.unsupportedPayload(CreateSpaceResultPayload.identifier)) {
        try await allowed.receive(unsupported)
    }
}

private func authenticatedSession(for deviceID: DeviceID) throws -> AuthenticatedRemoteSession {
    let hostEphemeral = ConnectionEphemeralKey()
    let deviceEphemeral = ConnectionEphemeralKey()
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: 1,
        hostID: HostID(),
        deviceID: deviceID,
        connectionID: UUID(),
        clientNonce: Data(repeating: 1, count: 32),
        serverNonce: Data(repeating: 2, count: 32),
        clientEphemeralPublicKey: deviceEphemeral.publicKey,
        serverEphemeralPublicKey: hostEphemeral.publicKey,
        route: .lan
    )
    let keys = try ConnectionAuthenticator.deriveKeys(participant: .host, ephemeralKey: hostEphemeral, peerEphemeralPublicKey: deviceEphemeral.publicKey, binding: binding)
    return AuthenticatedRemoteSession(connectionID: binding.connectionID, deviceID: deviceID, route: .lan, binding: binding, keys: keys)
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

@Test func localHostReplaysJournalEventsOrRequiresASnapshot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    for revision in 1...3 {
        _ = try await storage.appendJournalEvent(
            aggregateID: "host",
            aggregateType: "host",
            aggregateRevision: UInt64(revision),
            payloadIdentifier: "aizen.event.host@1",
            payloadSchemaVersion: 1,
            payloadBytes: Data([UInt8(revision)]),
            durability: .durable
        )
    }
    _ = try await storage.pruneJournalEvents(keepingMostRecent: 2)
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))

    let replay = try await transport.send(.init(
        messageID: "journal-replay",
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ReadJournalEventsQueryPayload(afterCursor: 2))
    ))
    let replayResult = try ReadJournalEventsResponsePayload(protobufBytes: replay.payload.protobufBytes)
    #expect(replayResult.events.map(\.cursor) == [3])
    #expect(!replayResult.snapshotRequired)

    let expired = try await transport.send(.init(
        messageID: "journal-expired",
        connectionSequence: 2,
        kind: .query,
        channel: .state,
        payload: try .init(ReadJournalEventsQueryPayload(afterCursor: 0))
    ))
    let expiredResult = try ReadJournalEventsResponsePayload(protobufBytes: expired.payload.protobufBytes)
    #expect(expiredResult.events.isEmpty)
    #expect(expiredResult.snapshotRequired)
    #expect(expiredResult.oldestCursor == 2)
    #expect(expiredResult.latestCursor == 3)
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

@Test func hostCreatesTerminalSessionsThroughThePlatformRuntime() async throws {
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
    let runtime = RecordingTerminalRuntime()
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage, terminalRuntime: runtime))
    let terminalID = SessionID()
    let envelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .terminal,
        payload: try .init(CreateTerminalSessionCommandPayload(
            terminalSessionID: terminalID.description,
            spaceID: space.id.description,
            executionContextID: context.id.description,
            title: "Server",
            initialCommand: "npm run dev"
        ))
    )

    let response = try await transport.send(envelope)
    let replay = try await transport.send(envelope)
    let session = try CreateTerminalSessionResultPayload(protobufBytes: response.payload.protobufBytes).session
    #expect(response.payload == replay.payload)
    #expect(session.id == terminalID)
    #expect(session.executionContextID == context.id)
    #expect(session.tmuxSessionName == "aizen-terminal")
    let storedSession = try #require(try await storage.load().terminalSessions.first)
    #expect(storedSession.id == session.id)
    #expect(storedSession.tmuxSessionName == session.tmuxSessionName)
    #expect(await runtime.createdTerminalID == terminalID)
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
    let envelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(CreateSpaceCommandPayload(name: "Vivy", icon: "sparkles"))
    )
    let response = try await transport.send(envelope)
    let replay = try await transport.send(envelope)
    let result = try CreateSpaceResultPayload(protobufBytes: response.payload.protobufBytes)
    #expect(response.payload == replay.payload)
    #expect(UUID(uuidString: result.spaceID) != nil)
    #expect(try await storage.load().spaces.map(\.name) == ["Vivy"])
    #expect(try await storage.load().commands.first?.spaceID == nil)
}

@Test func hostReplaysSpaceScopedCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact { $0.spaces.append(space) }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))

    let renameEnvelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(RenameSpaceCommandPayload(spaceID: space.id.description, name: "Aizen"))
    )
    let renameFirst = try await transport.send(renameEnvelope)
    let renameReplay = try await transport.send(renameEnvelope)
    #expect(renameFirst.payload == renameReplay.payload)
    #expect(try await storage.load().spaces == [Space(id: space.id, name: "Aizen")])

    let conversationEnvelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 2,
        kind: .command,
        channel: .state,
        payload: try .init(CreateConversationCommandPayload(spaceID: space.id.description, title: "Plan"))
    )
    let conversationFirst = try await transport.send(conversationEnvelope)
    let conversationReplay = try await transport.send(conversationEnvelope)
    #expect(conversationFirst.payload == conversationReplay.payload)
    #expect(try await storage.load().sessions.count == 1)
    #expect(try await storage.load().commands.count == 2)
}

@Test func hostReplaysAcceptedFolderImportCommands() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact { $0.spaces.append(space) }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage))
    let messageID = UUID().uuidString
    let envelope = ProtocolEnvelope(
        messageID: messageID,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(ImportLocalFolderCommandPayload(spaceID: space.id.description, path: folder.path))
    )
    let first = try await transport.send(envelope)
    let replay = try await transport.send(envelope)
    #expect(first.payload == replay.payload)
    #expect(try await storage.load().resources.count == 1)
    #expect(try await storage.load().commands.count == 1)
    #expect(try await storage.load().journalEvents.map(\.cursor) == [1])

    let resourceID = try ImportLocalFolderResultPayload(protobufBytes: first.payload.protobufBytes).resourceID
    let contextEnvelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 2,
        kind: .command,
        channel: .state,
        payload: try .init(CreateLocalFolderContextCommandPayload(spaceID: space.id.description, resourceID: resourceID))
    )
    let contextFirst = try await transport.send(contextEnvelope)
    let contextReplay = try await transport.send(contextEnvelope)
    #expect(contextFirst.payload == contextReplay.payload)
    #expect(try await storage.load().executionContexts.count == 1)
    #expect(try await storage.load().commands.count == 2)

    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan")
    _ = try await storage.transact { $0.sessions.append(session) }
    let contextID = try CreateLocalFolderContextResultPayload(protobufBytes: contextFirst.payload.protobufBytes).contextID
    let attachEnvelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 3,
        kind: .command,
        channel: .state,
        payload: try .init(AttachExecutionContextCommandPayload(sessionID: session.id.description, contextID: contextID))
    )
    let attachFirst = try await transport.send(attachEnvelope)
    let attachReplay = try await transport.send(attachEnvelope)
    #expect(attachFirst.payload == attachReplay.payload)
    #expect(try await storage.load().sessions.first?.executionContextID?.description == contextID)
    #expect(try await storage.load().commands.count == 3)

    let detachEnvelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 4,
        kind: .command,
        channel: .state,
        payload: try .init(DetachExecutionContextCommandPayload(sessionID: session.id.description))
    )
    let detachFirst = try await transport.send(detachEnvelope)
    let detachReplay = try await transport.send(detachEnvelope)
    #expect(detachFirst.payload == detachReplay.payload)
    #expect(try await storage.load().sessions.first?.executionContextID == nil)
    #expect(try await storage.load().commands.count == 4)

    let removeContextEnvelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 5,
        kind: .command,
        channel: .state,
        payload: try .init(RemoveExecutionContextCommandPayload(contextID: contextID))
    )
    let removeContextFirst = try await transport.send(removeContextEnvelope)
    let removeContextReplay = try await transport.send(removeContextEnvelope)
    #expect(removeContextFirst.payload == removeContextReplay.payload)
    #expect(try await storage.load().executionContexts.isEmpty)
    #expect(try await storage.load().commands.count == 5)
    let removeResourceEnvelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 6,
        kind: .command,
        channel: .state,
        payload: try .init(RemoveResourceCommandPayload(resourceID: resourceID))
    )
    let removeResourceFirst = try await transport.send(removeResourceEnvelope)
    let removeResourceReplay = try await transport.send(removeResourceEnvelope)
    #expect(removeResourceFirst.payload == removeResourceReplay.payload)
    #expect(try await storage.load().resources.isEmpty)
    #expect(try await storage.load().commands.count == 6)
    #expect(try await storage.load().journalEvents.map(\.cursor) == [1, 2, 3, 4, 5, 6])
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
    let envelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
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
    )
    let response = try await transport.send(envelope)
    let replay = try await transport.send(envelope)
    #expect(response.payload == replay.payload)
    #expect(try SendConversationResultPayload(protobufBytes: response.payload.protobufBytes).runID == runID.description)
    let snapshot = try await storage.load()
    #expect(snapshot.runs.first?.lifecycle == .succeeded)
    #expect(snapshot.runs.first?.executionContextID == snapshot.sessions.first?.executionContextID)
    #expect(snapshot.executionContexts.first?.kind == .managedTemporarySandbox)
    #expect((await runtime.prompted).map(\.1) == ["Make a plan"])
    #expect(snapshot.commands.count == 1)
}

@Test func hostReplaysRunCancellationCommands() async throws {
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
    let coordinator = ConversationRunCoordinator(storage: storage, runtime: PromptRecordingRuntime())
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage, conversationRuns: coordinator))
    let envelope = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(CancelRunCommandPayload(runID: run.id.description))
    )
    let first = try await transport.send(envelope)
    let replay = try await transport.send(envelope)
    #expect(first.payload == replay.payload)
    #expect(try await storage.load().runs.first?.lifecycle == .cancelled)
    #expect(try await storage.load().commands.count == 1)
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

@Test func temporarySandboxCleanupSkipsActiveRunsAndClearsExpiredContexts() async throws {
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
    let directory = await sandboxes.directoryURL(for: context)
    let run = Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id, lifecycle: .running)
    _ = try await storage.transact { $0.runs.append(run) }

    #expect(try await sandboxes.cleanupTemporarySandboxes(lastUsedBefore: .distantFuture).isEmpty)
    _ = try await storage.transact { $0.runs[0].lifecycle = .succeeded }
    #expect(try await sandboxes.cleanupTemporarySandboxes(lastUsedBefore: .distantFuture) == [context.id])
    #expect(try await storage.load().executionContexts.isEmpty)
    #expect(try await storage.load().sessions.first?.executionContextID == nil)
    #expect(try await storage.load().runs.first?.executionContextID == nil)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func sandboxTouchUpgradesMetadataCreatedBeforeRetentionTracking() async throws {
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
    let metadataURL = await sandboxes.directoryURL(for: context).appendingPathComponent("metadata.json")
    var legacyMetadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any])
    legacyMetadata.removeValue(forKey: "lastUsedAt")
    try JSONSerialization.data(withJSONObject: legacyMetadata).write(to: metadataURL)

    try await sandboxes.touch(context)
    #expect(String(decoding: try Data(contentsOf: metadataURL), as: UTF8.self).contains("lastUsedAt"))
}

@Test func sandboxCleanupRemovesOnlyUnownedUUIDDirectories() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let orphan = root.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
    let sandboxes = ManagedSandboxService(storage: storage, rootURL: root)

    #expect(try await sandboxes.cleanupOrphanedDirectories() == [orphan.standardizedFileURL])
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
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

@Test func hostForwardsAgentLaunchConfigurationThroughWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let updater = RecordingAgentLaunchUpdater()
    let host = LocalHost(
        storage: StorageRepository(url: root.appendingPathComponent("storage-v2.json")),
        agentLaunchConfiguration: updater
    )
    let command = ConfigureAgentLaunchCommandPayload(
        executablePath: "/usr/bin/env",
        arguments: ["codex-acp"],
        environment: ["TOKEN": "secret"]
    )
    let response = try await host.receive(.init(
        messageID: "configure-agent",
        connectionSequence: 1,
        kind: .command,
        channel: .control,
        payload: try .init(command)
    ))

    #expect(try ConfigureAgentLaunchResultPayload(protobufBytes: response.payload.protobufBytes) == .init())
    #expect(await updater.configuration == command)
}

private actor RecordingRuntime: RunRuntime {
    func start(run: Run) async throws {}
    func cancel(runID: RunID) async throws {}
}

private actor RecordingAgentLaunchUpdater: AgentLaunchConfigurationUpdating {
    private(set) var configuration: ConfigureAgentLaunchCommandPayload?

    func updateAgentLaunchConfiguration(_ configuration: ConfigureAgentLaunchCommandPayload) async throws {
        self.configuration = configuration
    }
}

private actor RecordingTerminalRuntime: TerminalRuntime {
    private(set) var createdTerminalID: SessionID?

    func createTerminal(
        id: SessionID,
        spaceID: SpaceID,
        executionContext: ExecutionContext,
        resource: Resource?,
        title: String?,
        initialCommand: String?
    ) async throws -> TerminalLaunch {
        createdTerminalID = id
        return TerminalLaunch(tmuxSessionName: "aizen-terminal", paneID: "%1")
    }
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
