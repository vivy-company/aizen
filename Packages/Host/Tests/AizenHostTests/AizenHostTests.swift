import Foundation
import CryptoKit
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

@Test func terminalTranscriptUsesOrderedBoundedRuntimeSnapshots() async {
    let terminal = SessionID()
    let transcripts = TerminalTranscriptRegistry(maximumBytes: 5)

    let first = await transcripts.record(terminalID: terminal, capture: Data("abc".utf8))
    #expect(first.sequence == 1)
    #expect(first.bytes == Data("abc".utf8))
    let second = await transcripts.record(terminalID: terminal, capture: Data("abcdef".utf8))
    #expect(second.sequence == 2)
    #expect(second.bytes == Data("bcdef".utf8))
    #expect(second.truncated)
    #expect(await transcripts.snapshot(terminalID: terminal, after: 2).bytes.isEmpty)
    let replay = await transcripts.snapshot(terminalID: terminal, after: 1)
    #expect(replay.sequence == 2)
    #expect(replay.bytes == Data("bcdef".utf8))
}

@Test func hostAttachesToBoundedTerminalOutput() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Private")
    let terminal = TerminalSession(spaceID: space.id, executionContextID: nil, title: nil, tmuxSessionName: "test", paneID: "%1", initialCommand: nil)
    _ = try await storage.transact { $0.spaces.append(space); $0.terminalSessions.append(terminal) }
    let runtime = RecordingTerminalRuntime()
    await runtime.setCapture(Data("abcdef".utf8))
    let host = LocalHost(storage: storage, terminalRuntime: runtime, terminalTranscripts: .init(maximumBytes: 4))
    let request = ProtocolEnvelope(messageID: "attach", connectionSequence: 1, kind: .query, channel: .terminal, payload: try .init(AttachTerminalQueryPayload(terminalSessionID: terminal.id.description, scrollbackBytes: 4)))
    let response = try await host.receive(request)
    let attached = try AttachTerminalResponsePayload(protobufBytes: response.payload.protobufBytes)
    #expect(attached.sequence == 1)
    #expect(attached.output == Data("cdef".utf8))
    #expect(!attached.truncated)
    let replay = ProtocolEnvelope(messageID: "attach-replay", connectionSequence: 2, kind: .query, channel: .terminal, payload: try .init(AttachTerminalQueryPayload(terminalSessionID: terminal.id.description, afterSequence: attached.sequence, scrollbackBytes: 4)))
    let replayResponse = try await host.receive(replay)
    #expect(try AttachTerminalResponsePayload(protobufBytes: replayResponse.payload.protobufBytes).output.isEmpty)
}

@Test func terminalControlLeasesExpireAndDeduplicateDeviceInput() async throws {
    let clock = TerminalLeaseTestClock(Date(timeIntervalSince1970: 1_000))
    let registry = TerminalControlLeaseRegistry(now: { clock.now })
    let terminalID = SessionID()
    let firstDevice = DeviceID()
    let secondDevice = DeviceID()

    let firstLease = try await registry.acquire(terminalID: terminalID, deviceID: firstDevice, duration: 30)
    #expect(firstLease.deviceID == firstDevice)
    await #expect(throws: TerminalControlLeaseRegistry.Error.controlledByAnotherDevice(firstDevice)) {
        _ = try await registry.acquire(terminalID: terminalID, deviceID: secondDevice)
    }
    try await registry.acceptOperation(terminalID: terminalID, deviceID: firstDevice, sequence: 1)
    await #expect(throws: TerminalControlLeaseRegistry.Error.replayedInputSequence) {
        try await registry.acceptOperation(terminalID: terminalID, deviceID: firstDevice, sequence: 1)
    }

    clock.advance(by: 31)
    #expect(await registry.currentLease(for: terminalID) == nil)
    let secondLease = try await registry.acquire(terminalID: terminalID, deviceID: secondDevice)
    #expect(secondLease.deviceID == secondDevice)
    await #expect(throws: TerminalControlLeaseRegistry.Error.notController) {
        try await registry.acceptOperation(terminalID: terminalID, deviceID: firstDevice, sequence: 2)
    }
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

    let invalidProof = PairingRequestPayload(tokenID: invitation.tokenID, pairingSecret: Data(repeating: 8, count: 32), hostID: host.hostID, deviceID: request.deviceID, deviceDisplayName: request.deviceDisplayName, devicePlatform: request.devicePlatform, deviceSigningPublicKey: request.deviceSigningPublicKey, deviceKeyAgreementPublicKey: request.deviceKeyAgreementPublicKey, route: request.route)
    await #expect(throws: SecurityError.pairingTokenRejected) {
        try await registry.submit(invalidProof)
    }
    #expect(await registry.pending().isEmpty)

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
        terminalControl: TerminalControlLeaseRegistry(),
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
        terminalControl: TerminalControlLeaseRegistry(),
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

    let localOnlyApproval = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 3,
        kind: .command,
        channel: .control,
        payload: try .init(ApprovePairingRequestCommandPayload(tokenID: UUID(), capabilities: ["host.read"]))
    )
    await #expect(throws: RemoteHostAuthorizationError.unsupportedPayload(ApprovePairingRequestCommandPayload.identifier)) {
        try await allowed.receive(localOnlyApproval)
    }
}

@Test func remoteHostEndpointRequiresGitPushCapabilityForRepositoryPushes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Private")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [.init(capability: .gitPull, spaceIDs: [space.id], resourceIDs: [resource.id])]))
    let endpoint = RemoteHostEndpoint(
        endpoint: LocalHost(storage: storage, repositoryPusher: RecordingRepositoryPusher()),
        storage: storage,
        authorization: DeviceAuthorizationGate(storage: storage),
        rateLimiter: RemoteRequestRateLimiter(),
        terminalControl: TerminalControlLeaseRegistry(),
        session: try authenticatedSession(for: device.deviceID),
        source: RemoteRequestSource("192.168.1.20")
    )
    let push = ProtocolEnvelope(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(PushRepositoryCommandPayload(resourceID: resource.id.description, expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64))))
    await #expect(throws: DeviceAuthorizationError.capabilityDenied(.gitPush)) {
        try await endpoint.receive(push)
    }
}

@Test func remoteHostEndpointRequiresScopedXcodeBuildCapabilityForOperationCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Private")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "Folder", details: .hostPrivate(.init(rawValue: "local-folder:\(root.path)")))
    let operation = AizenCore.Operation(spaceID: space.id, resourceID: resource.id, lifecycle: .running, progress: 0)
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource); $0.operations.append(operation) }
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [.init(capability: .xcodeRead, spaceIDs: [space.id], resourceIDs: [resource.id])]))
    let endpoint = RemoteHostEndpoint(
        endpoint: LocalHost(storage: storage),
        storage: storage,
        authorization: DeviceAuthorizationGate(storage: storage),
        rateLimiter: RemoteRequestRateLimiter(),
        terminalControl: TerminalControlLeaseRegistry(),
        session: try authenticatedSession(for: device.deviceID),
        source: RemoteRequestSource("192.168.1.20")
    )
    let cancel = ProtocolEnvelope(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(CancelOperationCommandPayload(operationID: operation.id.description)))
    await #expect(throws: DeviceAuthorizationError.capabilityDenied(.xcodeBuild)) {
        try await endpoint.receive(cancel)
    }
    let log = ProtocolEnvelope(
        messageID: UUID().uuidString,
        connectionSequence: 2,
        kind: .query,
        channel: .state,
        payload: try .init(ReadOperationLogQueryPayload(operationID: operation.id.description, maximumBytes: 4_096))
    )
    let response = try await endpoint.receive(log)
    #expect(try ReadOperationLogResponsePayload(protobufBytes: response.payload.protobufBytes).chunks.isEmpty)
}

@Test func remoteTerminalControlOwnsAndOrdersRuntimeTraffic() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Private")
    let terminal = TerminalSession(
        id: SessionID(),
        spaceID: space.id,
        executionContextID: nil,
        title: "Shell",
        tmuxSessionName: "aizen-test",
        paneID: "%1",
        initialCommand: nil
    )
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.terminalSessions.append(terminal)
    }
    let device = DevicePublicIdentity(
        deviceID: DeviceID(),
        displayName: "Phone",
        platform: "iOS",
        cryptographicIdentity: LocalCryptographicIdentity().publicIdentity()
    )
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [
        .init(capability: .hostRead),
        .init(capability: .terminalControl, spaceIDs: [space.id])
    ]))
    let runtime = RecordingTerminalRuntime()
    let endpoint = RemoteHostEndpoint(
        endpoint: LocalHost(storage: storage, terminalRuntime: runtime),
        storage: storage,
        authorization: DeviceAuthorizationGate(storage: storage),
        ownerConfirmation: OwnerConfirmationGate(storage: storage, authority: ApprovingOwnerConfirmationAuthority()),
        rateLimiter: RemoteRequestRateLimiter(),
        terminalControl: TerminalControlLeaseRegistry(),
        session: try authenticatedSession(for: device.deviceID),
        source: RemoteRequestSource("192.168.1.20")
    )

    let hello = ProtocolEnvelope(
        messageID: "hello",
        connectionSequence: 0,
        kind: .hello,
        channel: .control,
        payload: try .init(HelloPayload(minimumProtocolGeneration: 1, maximumProtocolGeneration: 1, productVersion: "test"))
    )
    let capabilities = try CapabilitiesPayload(protobufBytes: (try await endpoint.receive(hello)).payload.protobufBytes)
    #expect(capabilities.identifiers.contains(AcquireTerminalControlCommandPayload.identifier))
    #expect(capabilities.identifiers.contains(ReleaseTerminalControlCommandPayload.identifier))
    #expect(capabilities.identifiers.contains(TerminalControlLeaseResultPayload.identifier))

    let acquire = ProtocolEnvelope(
        messageID: "acquire",
        connectionSequence: 1,
        kind: .command,
        channel: .terminal,
        payload: try .init(AcquireTerminalControlCommandPayload(terminalSessionID: terminal.id.description))
    )
    let leaseResponse = try await endpoint.receive(acquire)
    let lease = try TerminalControlLeaseResultPayload(protobufBytes: leaseResponse.payload.protobufBytes)
    #expect(lease.terminalSessionID == terminal.id.description)
    #expect(lease.controllerDeviceID == device.deviceID.description)

    let input = ProtocolEnvelope(
        messageID: "input",
        connectionSequence: 2,
        kind: .command,
        channel: .terminal,
        payload: try .init(TerminalInputCommandPayload(terminalSessionID: terminal.id.description, sequence: 1, input: Data("echo hi\\n".utf8)))
    )
    let inputResponse = try await endpoint.receive(input)
    #expect(try TerminalOperationResultPayload(protobufBytes: inputResponse.payload.protobufBytes).sequence == 1)
    #expect(await runtime.inputs == [Data("echo hi\\n".utf8)])

    let resize = ProtocolEnvelope(
        messageID: "resize",
        connectionSequence: 3,
        kind: .command,
        channel: .terminal,
        payload: try .init(TerminalResizeCommandPayload(terminalSessionID: terminal.id.description, sequence: 2, columns: 120, rows: 40))
    )
    let resizeResponse = try await endpoint.receive(resize)
    #expect(try TerminalOperationResultPayload(protobufBytes: resizeResponse.payload.protobufBytes).sequence == 2)
    let resizes = await runtime.resizes
    #expect(resizes.count == 1)
    #expect(resizes.first?.0 == 120)
    #expect(resizes.first?.1 == 40)

    await #expect(throws: TerminalControlLeaseRegistry.Error.replayedInputSequence) {
        try await endpoint.receive(input)
    }
    #expect(await runtime.inputs == [Data("echo hi\\n".utf8)])

    let release = ProtocolEnvelope(
        messageID: "release",
        connectionSequence: 4,
        kind: .command,
        channel: .terminal,
        payload: try .init(ReleaseTerminalControlCommandPayload(terminalSessionID: terminal.id.description))
    )
    let releaseResponse = try await endpoint.receive(release)
    #expect(try TerminalOperationResultPayload(protobufBytes: releaseResponse.payload.protobufBytes).sequence == 0)
}

@Test func remoteTerminalControlFailsClosedWithoutAPlatformOwnerConfirmationAuthority() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Private")
    let terminal = TerminalSession(spaceID: space.id, tmuxSessionName: "aizen-test", paneID: "%1")
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    _ = try await storage.transact { $0.spaces.append(space); $0.terminalSessions.append(terminal) }
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [.init(capability: .terminalControl, spaceIDs: [space.id])]))
    let endpoint = RemoteHostEndpoint(
        endpoint: LocalHost(storage: storage),
        storage: storage,
        authorization: DeviceAuthorizationGate(storage: storage),
        rateLimiter: RemoteRequestRateLimiter(),
        terminalControl: TerminalControlLeaseRegistry(),
        session: try authenticatedSession(for: device.deviceID),
        source: RemoteRequestSource("192.168.1.20")
    )
    let acquire = ProtocolEnvelope(messageID: "acquire", connectionSequence: 1, kind: .command, channel: .terminal, payload: try .init(AcquireTerminalControlCommandPayload(terminalSessionID: terminal.id.description)))

    await #expect(throws: OwnerConfirmationError.unavailable(.terminalControl)) {
        try await endpoint.receive(acquire)
    }
    #expect(try await storage.load().securityAuditRecords.last?.kind == .ownerConfirmationUnavailable)
}

@Test func blobTransferStoreResumesVerifiesAndCleansUp() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data("resumable blob".utf8)
    let store = try BlobTransferStore(directory: root)
    let descriptor = try await store.begin(byteCount: data.count, sha256: Data(SHA256.hash(data: data)))
    _ = try await store.append(id: descriptor.id, offset: 0, bytes: data.prefix(4))
    await #expect(throws: BlobTransferStore.Error.offset(expected: 4)) { try await store.append(id: descriptor.id, offset: 0, bytes: Data()) }
    _ = try await store.append(id: descriptor.id, offset: 4, bytes: data.dropFirst(4))
    let file = try await store.finish(id: descriptor.id)
    #expect(try Data(contentsOf: file) == data)
    let bad = try await store.begin(byteCount: 1, sha256: Data(repeating: 0, count: 32))
    _ = try await store.append(id: bad.id, offset: 0, bytes: Data([1]))
    await #expect(throws: BlobTransferStore.Error.integrity) { _ = try await store.finish(id: bad.id) }
    let cancelled = try await store.begin(byteCount: 1, sha256: Data(SHA256.hash(data: Data([1]))))
    await store.cancel(id: cancelled.id)
    await #expect(throws: BlobTransferStore.Error.unknown) { _ = try await store.append(id: cancelled.id, offset: 0, bytes: Data([1])) }
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

@Test func localHostReturnsTheClientProjectionSnapshotThroughWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:/private/repository")))
    let context = ExecutionContext(spaceID: space.id, kind: .repositoryCheckout, resourceID: resource.id, hostReference: .init(rawValue: "local-checkout:/private/repository"))
    let terminal = TerminalSession(spaceID: space.id, executionContextID: context.id, tmuxSessionName: "aizen-vivy", paneID: "%1")
    let operation = Operation(spaceID: space.id, lifecycle: .running, progress: 0.5)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
        $0.terminalSessions.append(terminal)
        $0.operations.append(operation)
    }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage, xcodeProjectInspector: StaticXcodeProjectInspector(schemes: ["App", "AppTests"])))
    let response = try await transport.send(.init(messageID: "spaces", connectionSequence: 1, kind: .query, channel: .state, payload: try .init(SnapshotRequestPayload())))
    let wireSnapshot = try SnapshotResponsePayload(protobufBytes: response.payload.protobufBytes)
    let snapshot = try JSONDecoder().decode(HostProjectionSnapshot.self, from: wireSnapshot.snapshot)
    #expect(snapshot.spaces.map(\.name) == ["Vivy"])
    #expect(snapshot.resources.first?.details == .some(.none))
    #expect(snapshot.executionContexts.first?.hostReference == nil)
    #expect(snapshot.terminalSessions == [terminal])
    #expect(snapshot.operations == [operation])
}

@Test func hostListsOperationsThroughTypedWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Operations")
    let operation = Operation(spaceID: space.id, lifecycle: .running, progress: 0.5)
    _ = try await storage.transact { $0.spaces.append(space); $0.operations.append(operation) }
    let response = try await LocalHost(storage: storage).receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ListOperationsQueryPayload(operationID: operation.id.description))
    ))
    #expect(try ListOperationsResponsePayload(protobufBytes: response.payload.protobufBytes).operations == [operation])
}

@Test func hostReadsBoundedDurableOperationLogsThroughTypedWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Operations")
    let operation = Operation(spaceID: space.id, lifecycle: .running, progress: 0)
    _ = try await storage.transact { $0.spaces.append(space); $0.operations.append(operation) }
    _ = try await storage.appendOperationLogChunk(operationID: operation.id, stream: .standardOutput, text: "compile\\n")
    _ = try await storage.appendOperationLogChunk(operationID: operation.id, stream: .standardError, text: "warning\\n")

    let response = try await LocalHost(storage: storage).receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ReadOperationLogQueryPayload(operationID: operation.id.description, maximumBytes: 64 * 1_024))
    ))
    let log = try ReadOperationLogResponsePayload(protobufBytes: response.payload.protobufBytes)
    #expect(log.chunks.map(\.text) == ["compile\\n", "warning\\n"])
    #expect(!log.truncated)
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

@Test func hostDiscoversWorkspaceBeforeProjectWithoutExposingItsPath() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("App.xcworkspace"), withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    _ = try await storage.transact { $0.spaces.append(space) }
    let transport = InProcessTransport(endpoint: LocalHost(storage: storage, xcodeProjectInspector: StaticXcodeProjectInspector(schemes: ["App", "AppTests"])))
    let imported = try await transport.send(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(ImportLocalFolderCommandPayload(spaceID: space.id.description, path: folder.path))
    ))
    let resourceID = try ImportLocalFolderResultPayload(protobufBytes: imported.payload.protobufBytes).resourceID
    let response = try await transport.send(.init(
        messageID: UUID().uuidString,
        connectionSequence: 2,
        kind: .query,
        channel: .state,
        payload: try .init(DiscoverXcodeProjectQueryPayload(resourceID: resourceID))
    ))
    let project = try #require(try DiscoverXcodeProjectResponsePayload(protobufBytes: response.payload.protobufBytes).project)
    #expect(project.resourceID.description == resourceID)
    #expect(project.id == "App.xcworkspace")
    #expect(project.name == "App")
    #expect(project.kind == .workspace)
    #expect(project.schemes == ["App", "AppTests"])
    #expect(project.configurations == ["Debug", "Release"])
    #expect(!project.id.contains(folder.path))
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

@Test func repositoryRefreshReportsMissingPathsAsRecoverableState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(
        spaceID: space.id,
        kind: .repository,
        title: "Moved repository",
        details: .hostPrivate(.init(rawValue: "local-repository:/definitely-not-aizen"))
    )
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
    }
    let host = LocalHost(storage: storage)

    let response = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(RefreshRepositoryResourceCommandPayload(resourceID: resource.id.description))
    ))

    #expect(try RefreshRepositoryResourceResultPayload(protobufBytes: response.payload.protobufBytes) == .init(
        resourceID: resource.id.description,
        availability: .missing
    ))
}

@Test func repositoryRefreshReportsBranchSubmodulesAndRebaseState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    let git = repository.appendingPathComponent(".git", isDirectory: true)
    try FileManager.default.createDirectory(at: git.appendingPathComponent("rebase-merge", isDirectory: true), withIntermediateDirectories: true)
    try Data("ref: refs/heads/feature/reignition\n".utf8).write(to: git.appendingPathComponent("HEAD"))
    try Data("[submodule \"shared\"]\n".utf8).write(to: repository.appendingPathComponent(".gitmodules"))
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(
        spaceID: space.id,
        kind: .repository,
        title: "Repository",
        details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)"))
    )
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
    }
    let host = LocalHost(storage: storage)

    let response = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(RefreshRepositoryResourceCommandPayload(resourceID: resource.id.description))
    ))

    #expect(try RefreshRepositoryResourceResultPayload(protobufBytes: response.payload.protobufBytes) == .init(
        resourceID: resource.id.description,
        availability: .available,
        branch: "feature/reignition",
        isDetached: false,
        hasSubmodules: true,
        isRebaseInProgress: true
    ))
}

@Test func repositoryRefreshReportsDetachedHead() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    let git = repository.appendingPathComponent(".git", isDirectory: true)
    try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
    try Data("0123456789abcdef\n".utf8).write(to: git.appendingPathComponent("HEAD"))
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(
        spaceID: space.id,
        kind: .repository,
        title: "Repository",
        details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)"))
    )
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
    }
    let host = LocalHost(storage: storage)

    let response = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(RefreshRepositoryResourceCommandPayload(resourceID: resource.id.description))
    ))

    #expect(try RefreshRepositoryResourceResultPayload(protobufBytes: response.payload.protobufBytes) == .init(
        resourceID: resource.id.description,
        availability: .available,
        isDetached: true
    ))
}

@Test func hostReturnsBoundedStructuredRepositoryStatusThroughWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(
        spaceID: space.id,
        kind: .repository,
        title: "Repository",
        details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)"))
    )
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
    }
    let reader = StaticRepositoryStatusReader(snapshot: .init(
        repositoryRevision: "repository-revision",
        indexRevision: "index-revision",
        entries: [.init(path: "Sources/App.swift", indexStatus: "M", worktreeStatus: " ")],
        truncated: false
    ))
    let host = LocalHost(storage: storage, repositoryStatusReader: reader)

    let response = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ReadRepositoryStatusQueryPayload(resourceID: resource.id.description, maximumEntries: 1))
    ))

    #expect(try ReadRepositoryStatusResponsePayload(protobufBytes: response.payload.protobufBytes) == .init(
        resourceID: resource.id.description,
        repositoryRevision: "repository-revision",
        indexRevision: "index-revision",
        entries: [.init(path: "Sources/App.swift", indexStatus: "M", worktreeStatus: " ")],
        truncated: false
    ))
    #expect(await reader.requestedURL == repository)
    #expect(await reader.requestedMaximumEntries == 1)
}

@Test func hostReturnsResourceScopedRepositoryDiffThroughWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let host = LocalHost(storage: storage, repositoryDiffReader: StaticRepositoryDiffReader())
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .query, channel: .state, payload: try .init(ReadRepositoryDiffQueryPayload(resourceID: resource.id.description, relativePath: "README.md", maximumBytes: 64))))
    #expect(try ReadRepositoryDiffResponsePayload(protobufBytes: response.payload.protobufBytes) == .init(resourceID: resource.id.description, repositoryRevision: "revision", indexRevision: "index", unifiedDiff: Data("diff".utf8), truncated: false))
}

@Test func hostReturnsBoundedRepositoryBranchesThroughWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let host = LocalHost(storage: storage, repositoryBranchReader: StaticRepositoryBranchReader())
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .query, channel: .state, payload: try .init(ReadRepositoryBranchesQueryPayload(resourceID: resource.id.description, maximumBranches: 1))))
    #expect(try ReadRepositoryBranchesResponsePayload(protobufBytes: response.payload.protobufBytes) == .init(resourceID: resource.id.description, repositoryRevision: "revision", indexRevision: "index", branches: [.init(name: "main", revision: "abc", isCurrent: true)], truncated: false))
}

@Test func hostRecordsRepositoryIndexUpdatesAsCompletedDurableOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let updater = RecordingRepositoryIndexUpdater(revision: String(repeating: "b", count: 64))
    let host = LocalHost(storage: storage, repositoryIndexUpdater: updater)
    let response = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(UpdateRepositoryIndexCommandPayload(
            resourceID: resource.id.description,
            relativePaths: ["README.md"],
            expectedIndexRevision: String(repeating: "a", count: 64),
            stage: true
        ))
    ))

    let result = try UpdateRepositoryIndexResultPayload(protobufBytes: response.payload.protobufBytes)
    let operation = try #require(try await storage.load().operations.first)
    #expect(operation.id.description == result.operationID)
    #expect(operation.spaceID == space.id)
    #expect(operation.lifecycle == .completed)
    #expect(operation.progress == 1)
    #expect(await updater.requestedURL == repository)
    #expect(await updater.requestedPaths == ["README.md"])
    #expect(await updater.stage)
}

@Test func hostRecordsRepositoryCommitsAsCompletedDurableOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let committer = RecordingRepositoryCommitter()
    let host = LocalHost(storage: storage, repositoryCommitter: committer)
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(CommitRepositoryCommandPayload(resourceID: resource.id.description, message: "Ship it", expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64), amend: false))))

    let result = try CommitRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
    let operation = try #require(try await storage.load().operations.first)
    #expect(operation.id.description == result.operationID)
    #expect(operation.lifecycle == .completed)
    #expect(await committer.message == "Ship it")
    #expect(!(await committer.amend))
}

@Test func hostRecordsRepositoryBranchUpdatesAsCompletedDurableOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let updater = RecordingRepositoryBranchUpdater()
    let host = LocalHost(storage: storage, repositoryBranchUpdater: updater)
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(UpdateRepositoryBranchCommandPayload(resourceID: resource.id.description, branchName: "feature/reignition", expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64), create: true))))

    let result = try UpdateRepositoryBranchResultPayload(protobufBytes: response.payload.protobufBytes)
    let operation = try #require(try await storage.load().operations.first)
    #expect(operation.id.description == result.operationID)
    #expect(operation.lifecycle == .completed)
    #expect(await updater.branchName == "feature/reignition")
    #expect(await updater.create)
}

@Test func hostRecordsRepositoryFetchesAsCompletedDurableOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let fetcher = RecordingRepositoryFetcher()
    let host = LocalHost(storage: storage, repositoryFetcher: fetcher)
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(FetchRepositoryCommandPayload(resourceID: resource.id.description, expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64)))))

    let result = try FetchRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
    let operation = try #require(try await storage.load().operations.first)
    #expect(operation.id.description == result.operationID)
    #expect(operation.lifecycle == .completed)
    #expect(await fetcher.requestedURL == repository)
}

@Test func hostRecordsRepositoryPullsAsCompletedDurableOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let host = LocalHost(storage: storage, repositoryPuller: RecordingRepositoryPuller())
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(PullRepositoryCommandPayload(resourceID: resource.id.description, expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64)))))
    let result = try PullRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
    let operation = try #require(try await storage.load().operations.first)
    #expect(operation.id.description == result.operationID)
    #expect(operation.lifecycle == .completed)
}

@Test func hostRecordsRepositoryPushesAsCompletedDurableOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Repository")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let host = LocalHost(storage: storage, repositoryPusher: RecordingRepositoryPusher())
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(PushRepositoryCommandPayload(resourceID: resource.id.description, expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64)))))
    let result = try PushRepositoryResultPayload(protobufBytes: response.payload.protobufBytes)
    let operation = try #require(try await storage.load().operations.first)
    #expect(operation.id.description == result.operationID)
    #expect(operation.lifecycle == .completed)
}

@Test func localHostListsExecutionContextFilesThroughTypedWire() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let checkout = root.appendingPathComponent("checkout", isDirectory: true)
    try FileManager.default.createDirectory(at: checkout.appendingPathComponent("Sources"), withIntermediateDirectories: true)
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
    let host = LocalHost(storage: storage)

    let response = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ListContextFilesQueryPayload(executionContextID: context.id.description))
    ))

    #expect(response.payload.identifier == ListContextFilesResponsePayload.identifier)
    #expect(try ListContextFilesResponsePayload(protobufBytes: response.payload.protobufBytes).entries == [
        .init(relativePath: "Sources", name: "Sources", isDirectory: true),
        .init(relativePath: "README.md", name: "README.md", isDirectory: false)
    ])

    let textResponse = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 2,
        kind: .query,
        channel: .state,
        payload: try .init(ReadContextTextFileQueryPayload(
            executionContextID: context.id.description,
            relativePath: "README.md"
        ))
    ))
    #expect(textResponse.payload.identifier == ReadContextTextFileResponsePayload.identifier)
    let text = try ReadContextTextFileResponsePayload(protobufBytes: textResponse.payload.protobufBytes)
    #expect(text.text == "readme")
    #expect(text.contentHash.count == 64)

    let searchResponse = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 3,
        kind: .query,
        channel: .state,
        payload: try .init(SearchContextFilesQueryPayload(
            executionContextID: context.id.description,
            query: "README",
            maximumMatches: 10
        ))
    ))
    #expect(searchResponse.payload.identifier == SearchContextFilesResponsePayload.identifier)
    #expect(try SearchContextFilesResponsePayload(protobufBytes: searchResponse.payload.protobufBytes).result.matches == [
        .init(relativePath: "README.md", lineNumber: 1, preview: "readme")
    ])
}

@Test func hostCreatesLinkedWorktreeContextsThroughAHostOperation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: source.appendingPathComponent(".git"), withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Worktrees")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Source", details: .hostPrivate(.init(rawValue: "local-repository:\(source.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let worktrees = RecordingLinkedWorktrees()
    let host = LocalHost(storage: storage, linkedWorktrees: worktrees)
    let destination = root.appendingPathComponent("feature", isDirectory: true)

    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(CreateLinkedWorktreeContextCommandPayload(spaceID: space.id.description, resourceID: resource.id.description, destinationPath: destination.path, branch: "feature/test", createBranch: true, baseBranch: "main"))))
    let result = try CreateLinkedWorktreeContextResultPayload(protobufBytes: response.payload.protobufBytes)
    let snapshot = try await storage.load()
    #expect(snapshot.executionContexts.first?.id.description == result.contextID)
    #expect(snapshot.executionContexts.first?.hostReference == .init(rawValue: "local-worktree:\(destination.path)"))
    #expect(snapshot.operations.first?.id.description == result.operationID)
    #expect(snapshot.operations.first?.lifecycle == .completed)
    let createdDestination = await worktrees.destination
    #expect(createdDestination?.path == destination.path)
}

@Test func hostCreatesIndependentCopyContextsThroughAHostOperation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Copies")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "Source", details: .hostPrivate(.init(rawValue: "local-folder:\(source.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let creator = RecordingIndependentContexts()
    let host = LocalHost(storage: storage, independentContexts: creator)
    let destination = root.appendingPathComponent("copy", isDirectory: true)
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(CreateIndependentContextCommandPayload(spaceID: space.id.description, resourceID: resource.id.description, destinationPath: destination.path, mode: .copy))))
    let result = try CreateIndependentContextResultPayload(protobufBytes: response.payload.protobufBytes)
    let snapshot = try await storage.load()
    #expect(snapshot.executionContexts.first?.id.description == result.contextID)
    #expect(snapshot.executionContexts.first?.kind == .copiedEnvironment)
    #expect(snapshot.operations.first?.id.description == result.operationID)
    let createdMode = await creator.mode
    #expect(createdMode == .copy)
}

@Test func executionContextFileServiceReturnsRelativeEntriesAndRejectsTraversal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let checkout = root.appendingPathComponent("checkout", isDirectory: true)
    try FileManager.default.createDirectory(at: checkout.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: checkout.appendingPathComponent("README.md"))
    try Data("secret".utf8).write(to: checkout.appendingPathComponent(".env"))
    try Data("private".utf8).write(to: checkout.appendingPathComponent("identity.pem"))
    try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".ssh", isDirectory: true), withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Files")
    let context = ExecutionContext(spaceID: space.id, kind: .repositoryCheckout, hostReference: .init(rawValue: "local-checkout:\(checkout.path)"))
    _ = try await storage.transact { $0.spaces.append(space); $0.executionContexts.append(context) }
    let service = ExecutionContextFileService(storage: storage)

    let entries = try await service.listDirectory(contextID: context.id)
    #expect(entries.map(\.relativePath) == ["Sources", "README.md"])
    #expect(try await service.readTextFile(contextID: context.id, relativePath: "README.md") == "hello")
    let search = try await service.searchText(contextID: context.id, query: "HELLO", maximumMatches: 10)
    #expect(search.matches == [.init(relativePath: "README.md", lineNumber: 1, preview: "hello")])
    #expect(!search.truncated)
    let helloHash = SHA256.hash(data: Data("hello".utf8)).map { String(format: "%02x", $0) }.joined()
    let replacementHash = try await service.replaceTextFile(contextID: context.id, relativePath: "README.md", expectedContentHash: helloHash, text: "updated")
    #expect(try await service.readTextFile(contextID: context.id, relativePath: "README.md") == "updated")
    #expect(replacementHash.count == 64)
    await #expect(throws: ExecutionContextFileService.Error.revisionConflict) {
        try await service.replaceTextFile(contextID: context.id, relativePath: "README.md", expectedContentHash: helloHash, text: "stale")
    }
    let updatedHash = SHA256.hash(data: Data("updated".utf8)).map { String(format: "%02x", $0) }.joined()
    let insertedHash = try await service.applyTextPatch(contextID: context.id, relativePath: "README.md", expectedContentHash: updatedHash, kind: .insert, startLine: 1, endLineExclusive: 1, replacementText: "second")
    #expect(try await service.readTextFile(contextID: context.id, relativePath: "README.md") == "updated\nsecond")
    let replacedHash = try await service.applyTextPatch(contextID: context.id, relativePath: "README.md", expectedContentHash: insertedHash, kind: .replace, startLine: 0, endLineExclusive: 1, replacementText: "first")
    #expect(try await service.readTextFile(contextID: context.id, relativePath: "README.md") == "first\nsecond")
    _ = try await service.applyTextPatch(contextID: context.id, relativePath: "README.md", expectedContentHash: replacedHash, kind: .delete, startLine: 1, endLineExclusive: 2, replacementText: "")
    #expect(try await service.readTextFile(contextID: context.id, relativePath: "README.md") == "first")
    await #expect(throws: ExecutionContextFileService.Error.revisionConflict) {
        try await service.applyTextPatch(contextID: context.id, relativePath: "README.md", expectedContentHash: replacedHash, kind: .insert, startLine: 0, endLineExclusive: 0, replacementText: "stale")
    }
    let firstHash = SHA256.hash(data: Data("first".utf8)).map { String(format: "%02x", $0) }.joined()
    await #expect(throws: ExecutionContextFileService.Error.invalidText("README.md")) {
        try await service.applyTextPatch(contextID: context.id, relativePath: "README.md", expectedContentHash: firstHash, kind: .delete, startLine: 0, endLineExclusive: 0, replacementText: "")
    }
    #expect(try await service.listDirectory(contextID: context.id, includeHidden: true).map(\.relativePath) == ["Sources", "README.md"])
    await #expect(throws: ExecutionContextFileService.Error.sensitivePath(".env")) {
        try await service.readTextFile(contextID: context.id, relativePath: ".env")
    }
    await #expect(throws: ExecutionContextFileService.Error.sensitivePath(".ssh/config")) {
        try await service.readTextFile(contextID: context.id, relativePath: ".ssh/config")
    }
    try Data(repeating: 0xFF, count: 2).write(to: checkout.appendingPathComponent("binary.dat"))
    await #expect(throws: ExecutionContextFileService.Error.invalidText("binary.dat")) {
        try await service.readTextFile(contextID: context.id, relativePath: "binary.dat")
    }
    try Data(repeating: 0, count: 1_048_577).write(to: checkout.appendingPathComponent("large.txt"))
    await #expect(throws: ExecutionContextFileService.Error.fileTooLarge("large.txt")) {
        try await service.readTextFile(contextID: context.id, relativePath: "large.txt")
    }
    await #expect(throws: ExecutionContextFileService.Error.invalidRelativePath("../outside")) {
        try await service.listDirectory(contextID: context.id, relativePath: "../outside")
    }
    await #expect(throws: ExecutionContextFileService.Error.invalidRelativePath("../outside")) {
        try await service.readTextFile(contextID: context.id, relativePath: "../outside")
    }
    for path in ["./README.md", "README.md/", "README\u{0}md"] {
        await #expect(throws: ExecutionContextFileService.Error.invalidRelativePath(path)) {
            try await service.readTextFile(contextID: context.id, relativePath: path)
        }
    }
}

@Test func hostOpensOnlyTheDiscoveredXcodeProjectThroughItsRuntime() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    let project = folder.appendingPathComponent("App.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Xcode")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "folder", details: .hostPrivate(.init(rawValue: "local-folder:\(folder.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let opener = RecordingXcodeProjectOpener()
    let host = LocalHost(storage: storage, xcodeProjectOpener: opener)
    let response = try await host.receive(.init(
        messageID: UUID().uuidString,
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(OpenXcodeProjectCommandPayload(resourceID: resource.id.description, projectID: "App.xcodeproj"))
    ))
    #expect(response.payload.identifier == OpenXcodeProjectResultPayload.identifier)
    #expect(await opener.openedURL == project)
}

@Test func hostBuildsValidatedXcodeProjectsThroughItsRuntime() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Xcode")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "folder", details: .hostPrivate(.init(rawValue: "local-folder:\(folder.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let builder = ControlledXcodeProjectBuilder()
    let host = LocalHost(storage: storage, xcodeProjectInspector: StaticXcodeProjectInspector(schemes: ["App"]), xcodeProjectBuilder: builder)
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(BuildXcodeProjectCommandPayload(resourceID: resource.id.description, projectID: "App.xcodeproj", scheme: "App", destination: "platform=macOS"))))
    let result = try BuildXcodeProjectResultPayload(protobufBytes: response.payload.protobufBytes)
    #expect(try await storage.load().operations.first?.id.description == result.operationID)
    #expect(try await storage.load().operations.first?.lifecycle == .running)
    for _ in 0 ..< 20 where await builder.projectURL == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await builder.projectURL == folder.appendingPathComponent("App.xcodeproj"))
    #expect(await builder.action == .build)
    for _ in 0 ..< 20 where !(await builder.hasOutputSubscriber) {
        try await Task.sleep(for: .milliseconds(10))
    }
    await builder.emit(.init(stream: .standardOutput, text: "CompileSwift App.swift\\n"))
    await builder.complete()
    for _ in 0 ..< 20 where try await storage.load().operations.first?.lifecycle != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try await storage.load().operations.first?.lifecycle == .completed)
    #expect(try await storage.load().operations.first?.result?.summary == "Xcode build completed successfully.")
    #expect(try await storage.operationLogChunks(operationID: OperationID(rawValue: try #require(UUID(uuidString: result.operationID))), maximumBytes: 64 * 1_024).map(\.text) == ["CompileSwift App.swift\\n"])
}

@Test func hostStartsStructuredXcodeTestsThroughItsRuntime() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Xcode")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "folder", details: .hostPrivate(.init(rawValue: "local-folder:\(folder.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let builder = ControlledXcodeProjectBuilder()
    let host = LocalHost(storage: storage, xcodeProjectInspector: StaticXcodeProjectInspector(schemes: ["AppTests"]), xcodeProjectBuilder: builder)
    _ = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(BuildXcodeProjectCommandPayload(resourceID: resource.id.description, projectID: "App.xcodeproj", scheme: "AppTests", destination: "platform=macOS", action: .test))))
    for _ in 0 ..< 20 where await builder.action == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await builder.action == .test)
    await builder.complete()
}

@Test func hostCancelsRunningXcodeBuildOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Xcode")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "folder", details: .hostPrivate(.init(rawValue: "local-folder:\(folder.path)")))
    _ = try await storage.transact { $0.spaces.append(space); $0.resources.append(resource) }
    let builder = ControlledXcodeProjectBuilder()
    let host = LocalHost(storage: storage, xcodeProjectInspector: StaticXcodeProjectInspector(schemes: ["App"]), xcodeProjectBuilder: builder)
    let buildResponse = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 1, kind: .command, channel: .state, payload: try .init(BuildXcodeProjectCommandPayload(resourceID: resource.id.description, projectID: "App.xcodeproj", scheme: "App", destination: "platform=macOS"))))
    let build = try BuildXcodeProjectResultPayload(protobufBytes: buildResponse.payload.protobufBytes)
    let response = try await host.receive(.init(messageID: UUID().uuidString, connectionSequence: 2, kind: .command, channel: .state, payload: try .init(CancelOperationCommandPayload(operationID: build.operationID))))
    #expect(try CancelOperationResultPayload(protobufBytes: response.payload.protobufBytes).operationID == build.operationID)
    #expect(await builder.didCancel)
    #expect(try await storage.load().operations.first?.lifecycle == .cancelled)
}

private actor RecordingRuntime: RunRuntime {
    func start(run: Run) async throws {}
    func cancel(runID: RunID) async throws {}
}

private actor StaticRepositoryStatusReader: RepositoryStatusReading {
    private let snapshot: RepositoryStatusSnapshot
    private(set) var requestedURL: URL?
    private(set) var requestedMaximumEntries: Int?

    init(snapshot: RepositoryStatusSnapshot) {
        self.snapshot = snapshot
    }

    func status(at repositoryURL: URL, maximumEntries: Int) async throws -> RepositoryStatusSnapshot {
        requestedURL = repositoryURL
        requestedMaximumEntries = maximumEntries
        return snapshot
    }
}

private actor StaticRepositoryDiffReader: RepositoryDiffReading {
    func diff(at repositoryURL: URL, relativePath: String, maximumBytes: Int) async throws -> RepositoryDiffSnapshot {
        .init(repositoryRevision: "revision", indexRevision: "index", unifiedDiff: Data("diff".utf8), truncated: false)
    }
}

private actor StaticRepositoryBranchReader: RepositoryBranchReading {
    func branches(at repositoryURL: URL, maximumBranches: Int) async throws -> RepositoryBranchesSnapshot {
        .init(repositoryRevision: "revision", indexRevision: "index", branches: [.init(name: "main", revision: "abc", isCurrent: true)], truncated: false)
    }
}

private actor RecordingRepositoryIndexUpdater: RepositoryIndexUpdating {
    let revision: String
    private(set) var requestedURL: URL?
    private(set) var requestedPaths: [String] = []
    private(set) var stage = false

    init(revision: String) { self.revision = revision }

    func updateIndex(at repositoryURL: URL, relativePaths: [String], expectedIndexRevision: String, stage: Bool) async throws -> String {
        requestedURL = repositoryURL
        requestedPaths = relativePaths
        self.stage = stage
        return revision
    }
}

private actor RecordingRepositoryCommitter: RepositoryCommitting {
    private(set) var message: String?
    private(set) var amend = false

    func commit(at repositoryURL: URL, message: String, expectedRepositoryRevision: String, expectedIndexRevision: String, amend: Bool) async throws -> RepositoryCommitResult {
        self.message = message
        self.amend = amend
        return .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor RecordingRepositoryBranchUpdater: RepositoryBranchUpdating {
    private(set) var branchName: String?
    private(set) var create = false

    func updateBranch(at repositoryURL: URL, branchName: String, expectedRepositoryRevision: String, expectedIndexRevision: String, create: Bool) async throws -> RepositoryBranchUpdateResult {
        self.branchName = branchName
        self.create = create
        return .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor RecordingRepositoryFetcher: RepositoryFetching {
    private(set) var requestedURL: URL?

    func fetch(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult {
        requestedURL = repositoryURL
        return .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor RecordingRepositoryPuller: RepositoryPulling {
    func pull(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult {
        .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor RecordingRepositoryPusher: RepositoryPushing {
    func push(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult {
        .init(repositoryRevision: String(repeating: "c", count: 40), indexRevision: String(repeating: "b", count: 64))
    }
}

private actor RecordingLinkedWorktrees: LinkedWorktreeCreating {
    private(set) var destination: URL?
    func createLinkedWorktree(source: URL, destination: URL, branch: String, createBranch: Bool, baseBranch: String?) async throws { self.destination = destination }
}

private actor RecordingIndependentContexts: IndependentContextCreating {
    private(set) var mode: IndependentContextMode?
    func createIndependentContext(source: URL, destination: URL, mode: IndependentContextMode) async throws { self.mode = mode }
}

private actor RecordingXcodeProjectOpener: XcodeProjectOpening {
    private(set) var openedURL: URL?
    func openXcodeProject(at url: URL) async throws { openedURL = url }
}

private struct StaticXcodeProjectInspector: XcodeProjectInspecting {
    let schemes: [String]
    func schemes(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) async throws -> [String] { schemes }
    func configurations(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) async throws -> [String] { ["Debug", "Release"] }
}

private actor ControlledXcodeProjectBuilder: XcodeProjectBuilding, XcodeBuildRunning {
    private(set) var projectURL: URL?
    private(set) var action: XcodeProjectAction?
    private(set) var didCancel = false
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false
    private let outputStream: AsyncStream<XcodeBuildOutput>
    private let outputContinuation: AsyncStream<XcodeBuildOutput>.Continuation
    private(set) var hasOutputSubscriber = false

    init() {
        var continuation: AsyncStream<XcodeBuildOutput>.Continuation?
        outputStream = AsyncStream { continuation = $0 }
        outputContinuation = continuation!
    }

    func startXcodeProjectBuild(at url: URL, kind: XcodeProjectDescriptor.Kind, scheme: String, destination: String, action: XcodeProjectAction) async throws -> any XcodeBuildRunning {
        projectURL = url
        self.action = action
        return self
    }

    func waitForCompletion() async throws {
        if completed { return }
        if didCancel { throw CancellationError() }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func output() async -> AsyncStream<XcodeBuildOutput> {
        hasOutputSubscriber = true
        return outputStream
    }

    func emit(_ output: XcodeBuildOutput) {
        outputContinuation.yield(output)
    }

    func complete() {
        completed = true
        continuation?.resume()
        continuation = nil
        outputContinuation.finish()
    }

    func cancel() {
        didCancel = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        outputContinuation.finish()
    }
}

private actor RecordingAgentLaunchUpdater: AgentLaunchConfigurationUpdating {
    private(set) var configuration: ConfigureAgentLaunchCommandPayload?

    func updateAgentLaunchConfiguration(_ configuration: ConfigureAgentLaunchCommandPayload) async throws {
        self.configuration = configuration
    }
}

private struct ApprovingOwnerConfirmationAuthority: OwnerConfirmationAuthority {
    func confirm(_ request: OwnerConfirmationRequest) async -> OwnerConfirmationDecision {
        .approved
    }
}

private actor RecordingTerminalRuntime: TerminalRuntime {
    private(set) var createdTerminalID: SessionID?
    private(set) var inputs: [Data] = []
    private(set) var resizes: [(Int, Int)] = []
    private var capture: Data = .init()

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

    func sendInput(to session: TerminalSession, input: Data) async throws {
        inputs.append(input)
    }

    func resize(session: TerminalSession, columns: Int, rows: Int) async throws {
        resizes.append((columns, rows))
    }

    func setCapture(_ capture: Data) { self.capture = capture }

    func captureOutput(for session: TerminalSession, maximumBytes: Int) async throws -> Data {
        Data(capture.suffix(maximumBytes))
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

private final class TerminalLeaseTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}
