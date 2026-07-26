@testable import AizenCLIContracts
import AizenCore
import Foundation
import Testing

@Test func parserSeparatesPositionalsOptionsAndFlags() throws {
    let parsed = try parseArguments(["space", "list", "--json", "--workspace", "Core", "--no-color"])

    #expect(parsed.positionals == ["space", "list"])
    #expect(parsed.options == ["workspace": "Core"])
    #expect(parsed.flags == ["json", "no-color"])
}

@Test func parserRejectsOptionsWithoutValues() {
    #expect(throws: CLIError.invalidArguments("Missing value for --workspace")) {
        _ = try parseArguments(["--workspace"])
    }
}

@Test func exitCodesReserveDistinctHostFailures() {
    #expect(ExitCode.hostUnavailable.rawValue == 7)
    #expect(ExitCode.incompatibleHost.rawValue == 8)
    #expect(ExitCode.commandFailed.rawValue == 9)
    #expect(ExitCode.hostBlocked.rawValue == 10)
    #expect(ExitCode.hostTimeout.rawValue == 11)
}

@Test func jsonEncoderProducesSortedPrettyAndLineSafeFixtures() throws {
    struct Fixture: Encodable { let z: Int; let a: String }

    #expect(try encodeJSON(Fixture(z: 2, a: "one")) == "{\n  \"a\" : \"one\",\n  \"z\" : 2\n}")
    #expect(try encodeJSON(Fixture(z: 2, a: "one"), prettyPrinted: false) == "{\"a\":\"one\",\"z\":2}")
}

@Test func operationJSONFixtureIsStable() throws {
    let operation = Operation(
        id: OperationID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
        spaceID: SpaceID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
        lifecycle: .failed,
        progress: 0.5,
        failureDescription: "Build failed"
    )

    let payload = OperationPayload(operation: .init(operation: operation))
    let encoded = try encodeJSON(payload)
    #expect(encoded == "{\n  \"operation\" : {\n    \"failure\" : \"Build failed\",\n    \"id\" : \"11111111-1111-1111-1111-111111111111\",\n    \"lifecycle\" : \"failed\",\n    \"progress\" : 0.5,\n    \"sessionID\" : null,\n    \"spaceID\" : \"22222222-2222-2222-2222-222222222222\"\n  }\n}")
}

@Test func selectedSpaceStorePersistsOnlyTheExplicitSpaceID() {
    let suiteName = "AizenCLIContractsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = CLISelectedSpaceStore(defaults: defaults)
    let spaceID = SpaceID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)

    #expect(store.selectedSpaceID() == nil)
    store.select(spaceID)
    #expect(store.selectedSpaceID() == spaceID)
    store.clear()
    #expect(store.selectedSpaceID() == nil)
}
