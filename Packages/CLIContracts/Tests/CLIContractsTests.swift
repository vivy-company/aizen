import AizenCLIContracts
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
