import Foundation

/// Tracks state of a single terminal.
struct TerminalState {
    let process: Process
    var outputData: Data = Data()
    var outputByteLimit: Int?
    var isReleased: Bool = false
    var wasTruncated: Bool = false
    var pipesClosed: Bool = false
    var exitWaiters: [CheckedContinuation<(exitCode: Int?, signal: String?), Never>] = []

    nonisolated var outputBuffer: String {
        String(decoding: outputData, as: UTF8.self)
    }

    nonisolated mutating func appendOutput(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        outputData.append(data)

        guard let outputByteLimit, outputData.count > outputByteLimit else {
            return
        }

        outputData = Data(outputData.suffix(outputByteLimit))
        wasTruncated = true
    }
}

/// Cached output for released terminals for UI display.
struct ReleasedTerminalOutput {
    let output: String
    let exitCode: Int?
}
