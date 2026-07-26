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
