import Foundation
import Testing
@testable import AizenTestSupport

@Test func moduleLoads() {
    _ = AizenTestSupportModule.self
}

@Test func clockAndIdentifiersAreDeterministic() {
    var clock = TestClock()
    clock.advance(by: 1.5)
    #expect(clock.now == Date(timeIntervalSince1970: 1.5))

    var generator = DeterministicIDGenerator(startingAt: 41)
    #expect(generator.next() == 41)
    #expect(generator.next() == 42)
}

@Test func temporaryDirectoriesAreIsolated() throws {
    let directory = try TemporaryDirectory()
    #expect(directory.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    #expect(FileManager.default.fileExists(atPath: directory.url.path))
}
