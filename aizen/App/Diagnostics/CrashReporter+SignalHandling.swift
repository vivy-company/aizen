//
//  CrashReporter+SignalHandling.swift
//  aizen
//

import Foundation
import os.log

extension CrashReporter {
    // MARK: - Signal Handlers

    func setupSignalHandlers() {
        signal(SIGABRT) { signal in
            CrashReporter.handleSignal(signal, name: "SIGABRT")
        }
        signal(SIGSEGV) { signal in
            CrashReporter.handleSignal(signal, name: "SIGSEGV")
        }
        signal(SIGBUS) { signal in
            CrashReporter.handleSignal(signal, name: "SIGBUS")
        }
        signal(SIGILL) { signal in
            CrashReporter.handleSignal(signal, name: "SIGILL")
        }
        signal(SIGFPE) { signal in
            CrashReporter.handleSignal(signal, name: "SIGFPE")
        }
    }

    private static func handleSignal(_ signal: Int32, name: String) {
        let stack = Thread.callStackSymbols
        writeEmergencyCrashLog(type: "signal", reason: name, stack: stack)

        Darwin.signal(signal, SIG_DFL)
        Darwin.raise(signal)
    }

    static func writeEmergencyCrashLog(type: String, reason: String, stack: [String]) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let crashDir = appSupport.appendingPathComponent("Aizen/CrashLogs", isDirectory: true)

        try? FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)

        let timestamp = iso8601Formatter.string(from: Date())
        let filename = "emergency_\(type)_\(timestamp).txt"
        let fileURL = crashDir.appendingPathComponent(filename)

        var content = """
        Aizen Crash Report
        Type: \(type)
        Reason: \(reason)
        Time: \(timestamp)

        Stack Trace:
        """

        for (index, frame) in stack.enumerated() {
            content += "\n\(index): \(frame)"
        }

        try? content.write(to: fileURL, atomically: false, encoding: String.Encoding.utf8)

        let logger = Logger.forCategory("CrashReporter")
        logger.critical("CRASH: \(type) - \(reason)")
    }
}
