//
//  ProcessExecutor+Support.swift
//  aizen
//

import Foundation

// SAFETY: Thread-safe via NSLock. Ensures continuation is only resumed once.
nonisolated final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func runOnce(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        block()
    }
}

/// Thread-safe data collector for process output
// SAFETY: Thread-safe via NSLock protecting all Data buffer mutations.
nonisolated final class DataCollector: @unchecked Sendable {
    private var stdoutData = Data()
    private var stderrData = Data()
    private let lock = NSLock()

    func appendStdout(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        stdoutData.append(data)
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        stderrData.append(data)
    }

    var stdoutString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }

    var stderrString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stderrData, encoding: .utf8) ?? ""
    }
}
