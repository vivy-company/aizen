import Foundation

/// Shared deterministic fixtures and adapters for protocol and integration tests.
public enum AizenTestSupportModule {}

/// A manually advanced clock. Production tests must not depend on wall-clock timing.
public struct TestClock: Sendable {
    public private(set) var now: Date

    public init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.now = now
    }

    public mutating func advance(by interval: TimeInterval) {
        precondition(interval >= 0, "A test clock cannot move backward")
        now.addTimeInterval(interval)
    }
}

/// A stable, process-local identifier sequence for fixtures and scripted transports.
public struct DeterministicIDGenerator: Sendable {
    private var nextValue: UInt64

    public init(startingAt value: UInt64 = 1) {
        self.nextValue = value
    }

    public mutating func next() -> UInt64 {
        let value = nextValue
        let (advanced, overflow) = nextValue.addingReportingOverflow(1)
        precondition(!overflow, "Deterministic test identifiers are exhausted")
        nextValue = advanced
        return value
    }
}

/// An isolated directory that always lives under the process temporary directory.
public final class TemporaryDirectory: @unchecked Sendable {
    public let url: URL
    private let fileManager: FileManager

    public init(prefix: String = "aizen-test") throws {
        self.fileManager = .default
        let root = fileManager.temporaryDirectory
        self.url = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        try? fileManager.removeItem(at: url)
    }
}
