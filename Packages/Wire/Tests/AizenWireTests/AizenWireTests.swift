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
