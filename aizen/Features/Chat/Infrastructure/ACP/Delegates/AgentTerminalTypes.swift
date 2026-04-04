import Foundation

/// Tracks state of a single terminal.
struct TerminalState {
    let process: Process
    var outputBuffer: String = ""
    var outputByteLimit: Int?
    var lastReadIndex: Int = 0
    var isReleased: Bool = false
    var wasTruncated: Bool = false
    var exitWaiters: [CheckedContinuation<(exitCode: Int?, signal: String?), Never>] = []
}

/// Cached output for released terminals for UI display.
struct ReleasedTerminalOutput {
    let output: String
    let exitCode: Int?
}
