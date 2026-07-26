import Foundation
import AizenCore
import SwiftProtobuf
import Testing
@testable import AizenWire

@Test func wireUsesTheCoreProtocolGeneration() {
    #expect(AizenWireModule.protocolGeneration == 1)
}

@Test func envelopesRoundTripAsDeterministicProtobuf() throws {
    let payload = TypedPayload(
        identifier: .init(rawValue: "aizen.control.hello@1"),
        schemaVersion: 1,
        protobufBytes: Data([0x08, 0x01]),
        stateAffecting: false
    )
    let envelope = ProtocolEnvelope(
        messageID: "fixture-hello",
        connectionSequence: 1,
        kind: .hello,
        channel: .control,
        payload: payload
    )

    let bytes = try envelope.serializedData()
    let repeatedBytes = try envelope.serializedData()
    let decodedEnvelope = try ProtocolEnvelope(serializedData: bytes)
    let debugJSON = try envelope.debugJSON()
    let fixtureURL = try #require(Bundle.module.url(forResource: "hello-envelope.pb", withExtension: "base64", subdirectory: "Fixtures"))
    let fixtureBytes = try #require(Data(base64Encoded: String(decoding: try Data(contentsOf: fixtureURL), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(bytes == repeatedBytes)
    #expect(bytes == fixtureBytes)
    #expect(decodedEnvelope == envelope)
    #expect(debugJSON.contains("fixture-hello"))
}

@Test func additiveProtobufFieldsAndUnknownPayloadsAreSafe() throws {
    var hello = AizenWireV1_Hello()
    hello.minimumProtocolGeneration = 1
    let knownBytes = try hello.serializedData()
    let newerBytes = knownBytes + Data([0x28, 0x01]) // Field 5 is unknown to this generated schema.
    #expect(try AizenWireV1_Hello(serializedBytes: newerBytes).minimumProtocolGeneration == 1)

    let registry = PayloadRegistry(identifiers: [.init(rawValue: "aizen.control.hello@1")])
    #expect(registry.disposition(for: .init(identifier: .init(rawValue: "aizen.optional.future@1"), schemaVersion: 1, protobufBytes: Data(), stateAffecting: false)) == .ignoredOptional)
    #expect(registry.disposition(for: .init(identifier: .init(rawValue: "aizen.event.future@1"), schemaVersion: 1, protobufBytes: Data(), stateAffecting: true)) == .snapshotRequired)
}

@Test func snapshotPayloadKeepsStorageBytesInsideProtobuf() throws {
    let storageBytes = Data("{\"schemaVersion\":2}".utf8)
    let payload = SnapshotResponsePayload(cursor: 42, snapshot: storageBytes)
    let decoded = try SnapshotResponsePayload(protobufBytes: payload.protobufBytes())
    #expect(decoded.cursor == 42)
    #expect(decoded.snapshot == storageBytes)
}

@Test func capabilitiesPayloadCarriesProductAndProtocolCompatibility() throws {
    let payload = CapabilitiesPayload(
        identifiers: [.init(rawValue: "aizen.query.space.list@1")],
        minimumProtocolGeneration: 1,
        maximumProtocolGeneration: 2,
        productVersion: "2.1.0",
        minimumCompatibleProductVersion: "2.0.0"
    )
    let decoded = try CapabilitiesPayload(protobufBytes: payload.protobufBytes())
    #expect(decoded == payload)
}

@Test func repositoryStatusPayloadsRoundTripWithBoundedEntries() throws {
    let resourceID = UUID().uuidString
    let query = ReadRepositoryStatusQueryPayload(resourceID: resourceID, maximumEntries: 2)
    #expect(try ReadRepositoryStatusQueryPayload(protobufBytes: query.protobufBytes()) == query)

    let response = ReadRepositoryStatusResponsePayload(
        resourceID: resourceID,
        repositoryRevision: "a".padding(toLength: 40, withPad: "a", startingAt: 0),
        indexRevision: "b".padding(toLength: 64, withPad: "b", startingAt: 0),
        entries: [
            .init(path: "Sources/App.swift", indexStatus: "M", worktreeStatus: " "),
            .init(path: "README.md", indexStatus: "?", worktreeStatus: "?")
        ],
        truncated: false
    )
    #expect(try ReadRepositoryStatusResponsePayload(protobufBytes: response.protobufBytes()) == response)

    var malformed = AizenWireV1_ReadRepositoryStatusQuery()
    malformed.resourceID = resourceID
    malformed.maximumEntries = ReadRepositoryStatusQueryPayload.maximumEntryLimit + 1
    #expect(throws: WireCodecError.invalidRepositoryStatusQuery) {
        try ReadRepositoryStatusQueryPayload(protobufBytes: malformed.serializedData())
    }
}

@Test func repositoryDiffPayloadsAreBoundedAndRejectTraversal() throws {
    let resourceID = UUID().uuidString
    let query = ReadRepositoryDiffQueryPayload(resourceID: resourceID, relativePath: "Sources/App.swift", maximumBytes: 512)
    #expect(try ReadRepositoryDiffQueryPayload(protobufBytes: query.protobufBytes()) == query)
    let response = ReadRepositoryDiffResponsePayload(resourceID: resourceID, repositoryRevision: "revision", indexRevision: "index", unifiedDiff: Data("diff --git a/App.swift b/App.swift".utf8), truncated: false)
    #expect(try ReadRepositoryDiffResponsePayload(protobufBytes: response.protobufBytes()) == response)

    var malformed = AizenWireV1_ReadRepositoryDiffQuery()
    malformed.resourceID = resourceID
    malformed.relativePath = "../secret"
    malformed.maximumBytes = 10
    #expect(throws: WireCodecError.invalidRepositoryDiffQuery) {
        try ReadRepositoryDiffQueryPayload(protobufBytes: malformed.serializedData())
    }
}

@Test func repositoryHistoryPayloadsRoundTrip() throws {
    let resourceID = UUID().uuidString
    let query = ReadRepositoryHistoryQueryPayload(resourceID: resourceID, maximumCommits: 2)
    #expect(try ReadRepositoryHistoryQueryPayload(protobufBytes: query.protobufBytes()) == query)
    let response = ReadRepositoryHistoryResponsePayload(resourceID: resourceID, repositoryRevision: "head", indexRevision: "index", branch: "main", isDetached: false, commits: [.init(revision: "abc", subject: "Seed", authorName: "Aizen", authoredAtUnixMilliseconds: 1)], truncated: false)
    #expect(try ReadRepositoryHistoryResponsePayload(protobufBytes: response.protobufBytes()) == response)
}

@Test func repositoryIndexUpdatePayloadsCarryTheDurableOperation() throws {
    let resourceID = UUID().uuidString
    let operationID = UUID().uuidString
    let command = UpdateRepositoryIndexCommandPayload(
        resourceID: resourceID,
        relativePaths: ["Sources/App.swift"],
        expectedIndexRevision: String(repeating: "a", count: 64),
        stage: true
    )
    let result = UpdateRepositoryIndexResultPayload(indexRevision: String(repeating: "b", count: 64), operationID: operationID)
    #expect(try UpdateRepositoryIndexCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try UpdateRepositoryIndexResultPayload(protobufBytes: result.protobufBytes()) == result)
}

@Test func repositoryBranchesPayloadsRoundTripWithBounds() throws {
    let resourceID = UUID().uuidString
    let query = ReadRepositoryBranchesQueryPayload(resourceID: resourceID, maximumBranches: 2)
    let response = ReadRepositoryBranchesResponsePayload(
        resourceID: resourceID,
        repositoryRevision: "head",
        indexRevision: "index",
        branches: [.init(name: "main", revision: "abc", isCurrent: true)],
        truncated: false
    )
    #expect(try ReadRepositoryBranchesQueryPayload(protobufBytes: query.protobufBytes()) == query)
    #expect(try ReadRepositoryBranchesResponsePayload(protobufBytes: response.protobufBytes()) == response)
}

@Test func repositoryCommitPayloadsCarryBothRevisionPreconditions() throws {
    let command = CommitRepositoryCommandPayload(
        resourceID: UUID().uuidString,
        message: "Ship it",
        expectedRepositoryRevision: "unborn:main",
        expectedIndexRevision: String(repeating: "a", count: 64),
        amend: false
    )
    let result = CommitRepositoryResultPayload(
        repositoryRevision: String(repeating: "c", count: 40),
        indexRevision: String(repeating: "b", count: 64),
        operationID: UUID().uuidString
    )
    #expect(try CommitRepositoryCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try CommitRepositoryResultPayload(protobufBytes: result.protobufBytes()) == result)
}

@Test func repositoryBranchUpdatePayloadsRejectUnsafeNames() throws {
    let command = UpdateRepositoryBranchCommandPayload(
        resourceID: UUID().uuidString,
        branchName: "feature/reignition",
        expectedRepositoryRevision: "head",
        expectedIndexRevision: String(repeating: "a", count: 64),
        create: true
    )
    let result = UpdateRepositoryBranchResultPayload(repositoryRevision: "head", indexRevision: String(repeating: "b", count: 64), operationID: UUID().uuidString)
    #expect(try UpdateRepositoryBranchCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try UpdateRepositoryBranchResultPayload(protobufBytes: result.protobufBytes()) == result)

    var malformed = AizenWireV1_UpdateRepositoryBranchCommand()
    malformed.resourceID = command.resourceID
    malformed.branchName = "../escape"
    malformed.expectedRepositoryRevision = "head"
    malformed.expectedIndexRevision = String(repeating: "a", count: 64)
    #expect(throws: WireCodecError.invalidRepositoryBranchCommand) {
        try UpdateRepositoryBranchCommandPayload(protobufBytes: malformed.serializedData())
    }
}

@Test func repositoryFetchPayloadsCarryRevisionPreconditions() throws {
    let command = FetchRepositoryCommandPayload(resourceID: UUID().uuidString, expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64))
    let result = FetchRepositoryResultPayload(repositoryRevision: "head", indexRevision: String(repeating: "b", count: 64), operationID: UUID().uuidString)
    #expect(try FetchRepositoryCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try FetchRepositoryResultPayload(protobufBytes: result.protobufBytes()) == result)
}

@Test func repositoryPullPayloadsCarryRevisionPreconditions() throws {
    let command = PullRepositoryCommandPayload(resourceID: UUID().uuidString, expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64))
    let result = PullRepositoryResultPayload(repositoryRevision: "head", indexRevision: String(repeating: "b", count: 64), operationID: UUID().uuidString)
    #expect(try PullRepositoryCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try PullRepositoryResultPayload(protobufBytes: result.protobufBytes()) == result)
}

@Test func repositoryPushPayloadsCarryRevisionPreconditions() throws {
    let command = PushRepositoryCommandPayload(resourceID: UUID().uuidString, expectedRepositoryRevision: "head", expectedIndexRevision: String(repeating: "a", count: 64))
    let result = PushRepositoryResultPayload(repositoryRevision: "head", indexRevision: String(repeating: "b", count: 64), operationID: UUID().uuidString)
    #expect(try PushRepositoryCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try PushRepositoryResultPayload(protobufBytes: result.protobufBytes()) == result)
}

@Test func operationCancellationPayloadsRequireOperationIDs() throws {
    let command = CancelOperationCommandPayload(operationID: UUID().uuidString)
    let result = CancelOperationResultPayload(operationID: UUID().uuidString)
    #expect(try CancelOperationCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try CancelOperationResultPayload(protobufBytes: result.protobufBytes()) == result)
}

@Test func xcodeBuildCommandsRejectUnboundedOrUnsupportedDestinations() throws {
    var command = AizenWireV1_BuildXcodeProjectCommand()
    command.resourceID = UUID().uuidString
    command.projectID = "App.xcodeproj"
    command.scheme = "App"
    command.destination = "platform=iOS Simulator,name=User Device"
    #expect(throws: WireCodecError.invalidXcodeBuildCommand) {
        try BuildXcodeProjectCommandPayload(protobufBytes: command.serializedData())
    }
}

@Test func xcodeBuildCommandsCarryStructuredTestActions() throws {
    let command = BuildXcodeProjectCommandPayload(resourceID: UUID().uuidString, projectID: "App.xcodeproj", scheme: "AppTests", destination: "platform=macOS", action: .test)
    #expect(try BuildXcodeProjectCommandPayload(protobufBytes: command.protobufBytes()) == command)
}

@Test func operationLogPayloadsKeepCursorsAndBoundedChunks() throws {
    let operationID = OperationID()
    let query = ReadOperationLogQueryPayload(operationID: operationID.description, afterSequence: 4, maximumBytes: 4_096)
    let response = ReadOperationLogResponsePayload(
        chunks: [OperationLogChunk(operationID: operationID, sequence: 5, stream: .standardError, text: "failure detail\\n")],
        truncated: true
    )

    #expect(try ReadOperationLogQueryPayload(protobufBytes: query.protobufBytes()) == query)
    #expect(try ReadOperationLogResponsePayload(protobufBytes: response.protobufBytes()) == response)
}

@Test func operationRecordsPreserveResourceAndFinalResults() throws {
    let operation = Operation(
        spaceID: SpaceID(),
        resourceID: ResourceID(),
        lifecycle: .completed,
        progress: 1,
        result: .init(summary: "Xcode tests completed successfully.", artifactIDs: [ArtifactID()])
    )
    let payload = ListOperationsResponsePayload(operations: [operation])

    #expect(try ListOperationsResponsePayload(protobufBytes: payload.protobufBytes()).operations == [operation])
}

@Test func contextFileSearchPayloadsKeepRelativeBoundedMatches() throws {
    let contextID = UUID().uuidString
    let query = SearchContextFilesQueryPayload(executionContextID: contextID, query: "reignition", maximumMatches: 25)
    let response = SearchContextFilesResponsePayload(result: .init(
        matches: [.init(relativePath: "Sources/App.swift", lineNumber: 8, preview: "let title = \\\"Reignition\\\"")],
        truncated: false
    ))

    #expect(try SearchContextFilesQueryPayload(protobufBytes: query.protobufBytes()) == query)
    #expect(try SearchContextFilesResponsePayload(protobufBytes: response.protobufBytes()) == response)
}

@Test func xcodeProjectDiscoveryCarriesBuildConfigurations() throws {
    let descriptor = XcodeProjectDescriptor(resourceID: ResourceID(), id: "App.xcodeproj", name: "App", kind: .project, schemes: ["App"], configurations: ["Debug", "Release"])
    let payload = DiscoverXcodeProjectResponsePayload(project: descriptor)
    #expect(try DiscoverXcodeProjectResponsePayload(protobufBytes: payload.protobufBytes()) == payload)
}

@Test func webResourceImportPayloadRoundTripsAsProtobuf() throws {
    let url = try #require(URL(string: "https://example.com/docs"))
    let payload = ImportWebResourceCommandPayload(spaceID: UUID().uuidString, url: url, title: "Docs")
    #expect(try ImportWebResourceCommandPayload(protobufBytes: payload.protobufBytes()) == payload)
}

@Test func authenticationPayloadsRoundTripAndRejectMalformedCryptoMaterial() throws {
    let hostID = HostID()
    let deviceID = DeviceID()
    let connectionID = UUID()
    let start = AuthenticationStartPayload(
        hostID: hostID,
        deviceID: deviceID,
        connectionID: connectionID,
        clientNonce: Data(repeating: 1, count: 32),
        deviceSigningPublicKey: Data(repeating: 2, count: 32),
        deviceKeyAgreementPublicKey: Data(repeating: 3, count: 32),
        clientEphemeralPublicKey: Data(repeating: 4, count: 32),
        route: "lan"
    )
    let challenge = AuthenticationChallengePayload(
        hostID: hostID,
        deviceID: deviceID,
        connectionID: connectionID,
        clientNonce: start.clientNonce,
        serverNonce: Data(repeating: 5, count: 32),
        hostSigningPublicKey: Data(repeating: 6, count: 32),
        hostKeyAgreementPublicKey: Data(repeating: 7, count: 32),
        serverEphemeralPublicKey: Data(repeating: 8, count: 32),
        route: "lan",
        hostSignature: Data(repeating: 9, count: 64)
    )
    let proof = AuthenticationProofPayload(connectionID: connectionID, deviceSignature: Data(repeating: 10, count: 64))
    #expect(try AuthenticationStartPayload(protobufBytes: start.protobufBytes()) == start)
    #expect(try AuthenticationChallengePayload(protobufBytes: challenge.protobufBytes()) == challenge)
    #expect(try AuthenticationProofPayload(protobufBytes: proof.protobufBytes()) == proof)

    var malformed = AizenWireV1_AuthenticationProof()
    malformed.connectionID = connectionID.uuidString
    malformed.deviceSignature = Data(repeating: 0, count: 63)
    #expect(throws: WireCodecError.invalidAuthenticationPayload) {
        try AuthenticationProofPayload(protobufBytes: malformed.serializedData())
    }
}

@Test func pairingRequestPayloadRoundTripsAndRejectsMalformedIdentity() throws {
    let payload = PairingRequestPayload(
        tokenID: UUID(), pairingSecret: Data(repeating: 1, count: 32), hostID: HostID(), deviceID: DeviceID(),
        deviceDisplayName: "Phone", devicePlatform: "iOS", deviceSigningPublicKey: Data(repeating: 2, count: 32),
        deviceKeyAgreementPublicKey: Data(repeating: 3, count: 32), route: "lan"
    )
    #expect(try PairingRequestPayload(protobufBytes: payload.protobufBytes()) == payload)
    #expect(try PairingPendingPayload(protobufBytes: PairingPendingPayload(tokenID: payload.tokenID).protobufBytes()).tokenID == payload.tokenID)

    var malformed = AizenWireV1_PairingRequest()
    malformed.tokenID = payload.tokenID.uuidString
    malformed.hostID = payload.hostID.description
    malformed.deviceID = payload.deviceID.description
    malformed.pairingSecret = Data(repeating: 1, count: 31)
    malformed.deviceDisplayName = "Phone"
    malformed.devicePlatform = "iOS"
    malformed.deviceSigningPublicKey = Data(repeating: 2, count: 32)
    malformed.deviceKeyAgreementPublicKey = Data(repeating: 3, count: 32)
    malformed.route = "lan"
    #expect(throws: WireCodecError.invalidAuthenticationPayload) {
        try PairingRequestPayload(protobufBytes: malformed.serializedData())
    }
}

@Test func resourceRecordsPreserveHostPrivateDetails() throws {
    let resource = Resource(
        spaceID: SpaceID(),
        kind: .repository,
        title: "Aizen",
        details: .hostPrivate(.init(rawValue: "local-repository:/tmp/aizen"))
    )
    let payload = ListResourcesResponsePayload(resources: [resource])
    #expect(try ListResourcesResponsePayload(protobufBytes: payload.protobufBytes()).resources == [resource])
}

@Test func terminalCreationPayloadsRoundTrip() throws {
    let session = TerminalSession(
        spaceID: SpaceID(),
        executionContextID: ExecutionContextID(),
        title: "Server",
        tmuxSessionName: "aizen-server",
        paneID: "%1",
        initialCommand: "npm run dev",
        createdAt: Date(timeIntervalSince1970: 1_234)
    )
    let command = CreateTerminalSessionCommandPayload(
        terminalSessionID: session.id.description,
        spaceID: session.spaceID.description,
        executionContextID: session.executionContextID!.description,
        title: session.title,
        initialCommand: session.initialCommand
    )

    #expect(try CreateTerminalSessionCommandPayload(protobufBytes: command.protobufBytes()) == command)
    #expect(try CreateTerminalSessionResultPayload(protobufBytes: CreateTerminalSessionResultPayload(session: session).protobufBytes()).session == session)
    let acquire = AcquireTerminalControlCommandPayload(terminalSessionID: session.id.description, leaseSeconds: 30)
    #expect(try AcquireTerminalControlCommandPayload(protobufBytes: acquire.protobufBytes()) == acquire)
    let input = TerminalInputCommandPayload(terminalSessionID: session.id.description, sequence: 1, input: Data("pwd\n".utf8))
    #expect(try TerminalInputCommandPayload(protobufBytes: input.protobufBytes()) == input)
    let resize = TerminalResizeCommandPayload(terminalSessionID: session.id.description, sequence: 2, columns: 120, rows: 40)
    #expect(try TerminalResizeCommandPayload(protobufBytes: resize.protobufBytes()) == resize)
    let lease = TerminalControlLeaseResultPayload(terminalSessionID: session.id.description, controllerDeviceID: DeviceID().description, expiresAt: Date(timeIntervalSince1970: 1_500))
    #expect(try TerminalControlLeaseResultPayload(protobufBytes: lease.protobufBytes()) == lease)
    let operation = TerminalOperationResultPayload(terminalSessionID: session.id.description, sequence: 2)
    #expect(try TerminalOperationResultPayload(protobufBytes: operation.protobufBytes()) == operation)
}

@Test func agentLaunchConfigurationPayloadRoundTrips() throws {
    let payload = ConfigureAgentLaunchCommandPayload(
        executablePath: "/usr/bin/env",
        arguments: ["codex-acp"],
        environment: ["API_TOKEN": "secret", "PATH": "/opt/homebrew/bin"]
    )

    #expect(try ConfigureAgentLaunchCommandPayload(protobufBytes: payload.protobufBytes()) == payload)
    #expect(try ConfigureAgentLaunchResultPayload(protobufBytes: ConfigureAgentLaunchResultPayload().protobufBytes()) == .init())
}

@Test func runEventPayloadRoundTrips() throws {
    let eventID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let spaceID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let sessionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    let runID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
    let event = RunEvent(
        id: eventID,
        sequence: 1,
        spaceID: SpaceID(rawValue: spaceID),
        sessionID: SessionID(rawValue: sessionID),
        runID: RunID(rawValue: runID),
        kind: .assistantTextDelta("Hello")
    )
    let payload = RunEventPayload(event: event)

    #expect(try RunEventPayload(protobufBytes: payload.protobufBytes()) == payload)
}

@Test func journalReplayPayloadRoundTripsTypedEvents() throws {
    let space = SpaceID()
    let event = JournalEvent(
        cursor: 4,
        spaceID: space,
        aggregateID: "command",
        aggregateType: "command",
        aggregateRevision: 1,
        occurredAt: Date(timeIntervalSince1970: 1_234),
        payloadIdentifier: "aizen.command-result.example@1",
        payloadSchemaVersion: 1,
        payloadBytes: Data([1, 2]),
        durability: .durable
    )
    let payload = ReadJournalEventsResponsePayload(events: [event], oldestCursor: 4, latestCursor: 4, snapshotRequired: false)
    #expect(try ReadJournalEventsResponsePayload(protobufBytes: payload.protobufBytes()) == payload)
}
