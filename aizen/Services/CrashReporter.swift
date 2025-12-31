//
//  CrashReporter.swift
//  aizen
//
//  MetricKit-based crash and diagnostic reporting
//

import Foundation
import MetricKit
import os.log

/// Handles crash reporting and diagnostic collection using MetricKit
@MainActor
final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReporter()
    private static let iso8601Formatter = ISO8601DateFormatter()

    private let logger = Logger.forCategory("CrashReporter")
    private let crashLogDirectory: URL

    private override init() {
        // Store crash logs in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        crashLogDirectory = appSupport.appendingPathComponent("Aizen/CrashLogs", isDirectory: true)

        super.init()

        // Create crash log directory if needed
        try? FileManager.default.createDirectory(at: crashLogDirectory, withIntermediateDirectories: true)

        // Register for MetricKit diagnostics
        MXMetricManager.shared.add(self)

        // Set up uncaught exception handler
        NSSetUncaughtExceptionHandler { exception in
            let logger = Logger.forCategory("CrashReporter")
            logger.critical("Uncaught exception: \(exception.name.rawValue) - \(exception.reason ?? "no reason")")
            logger.critical("Stack trace:\n\(exception.callStackSymbols.joined(separator: "\n"))")

            // Write to file synchronously before crash
            CrashReporter.writeEmergencyCrashLog(
                type: "exception",
                reason: "\(exception.name.rawValue): \(exception.reason ?? "unknown")",
                stack: exception.callStackSymbols
            )
        }

        // Set up signal handlers for Swift runtime crashes
        setupSignalHandlers()

        logger.info("CrashReporter initialized")
    }

    /// Start crash reporting (call from app init)
    func start() {
        // Check for previous crash logs
        checkPreviousCrashes()
    }

    // MARK: - MXMetricManagerSubscriber

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        Task { @MainActor in
            for payload in payloads {
                logger.debug("Received metric payload: \(payload.timeStampBegin) - \(payload.timeStampEnd)")
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            for payload in payloads {
                handleDiagnosticPayload(payload)
            }
        }
    }

    // MARK: - Diagnostic Handling

    private func handleDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        // Handle crash diagnostics
        if let crashes = payload.crashDiagnostics {
            for crash in crashes {
                handleCrash(crash)
            }
        }

        // Handle hang diagnostics (UI freezes)
        if let hangs = payload.hangDiagnostics {
            for hang in hangs {
                handleHang(hang)
            }
        }

        // Handle CPU exceptions
        if let cpuExceptions = payload.cpuExceptionDiagnostics {
            for exception in cpuExceptions {
                handleCPUException(exception)
            }
        }
    }

    private func handleCrash(_ crash: MXCrashDiagnostic) {
        logger.error("Crash detected:")
        logger.error("  Exception type: \(crash.exceptionType?.description ?? "unknown")")
        logger.error("  Exception code: \(crash.exceptionCode?.description ?? "unknown")")
        logger.error("  Signal: \(crash.signal?.description ?? "unknown")")
        logger.error("  Termination reason: \(crash.terminationReason ?? "unknown")")

        // Save crash report to file
        saveCrashReport(crash)
    }

    private func handleHang(_ hang: MXHangDiagnostic) {
        logger.warning("UI hang detected:")
        logger.warning("  Duration: \(hang.hangDuration.description)")

        // Log call stack for debugging
        if let jsonData = try? hang.jsonRepresentation() {
            saveReport(jsonData, type: "hang")
        }
    }

    private func handleCPUException(_ exception: MXCPUExceptionDiagnostic) {
        logger.warning("CPU exception detected:")
        logger.warning("  Total CPU time: \(exception.totalCPUTime.description)")
        logger.warning("  Total sampled time: \(exception.totalSampledTime.description)")
    }

    // MARK: - Report Storage

    private func saveCrashReport(_ crash: MXCrashDiagnostic) {
        guard let jsonData = try? crash.jsonRepresentation() else {
            logger.error("Failed to serialize crash report")
            return
        }

        saveReport(jsonData, type: "crash")
    }

    private func saveReport(_ data: Data, type: String) {
        let timestamp = Self.iso8601Formatter.string(from: Date())
        let filename = "\(type)_\(timestamp).json"
        let fileURL = crashLogDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            logger.info("Saved \(type) report: \(filename)")
        } catch {
            logger.error("Failed to save \(type) report: \(error.localizedDescription)")
        }
    }

    private func checkPreviousCrashes() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: crashLogDirectory, includingPropertiesForKeys: nil)
            let crashFiles = files.filter { $0.lastPathComponent.hasPrefix("crash_") }

            if !crashFiles.isEmpty {
                logger.warning("Found \(crashFiles.count) previous crash report(s)")
            }
        } catch {
            // Directory may not exist yet
        }
    }

    // MARK: - Manual Logging

    /// Log a critical error that may lead to crash
    func logCriticalError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let location = "\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function)"
        logger.critical("CRITICAL: \(message) at \(location)")
    }

    /// Log a potential race condition
    func logRaceCondition(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let location = "\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function)"
        logger.error("RACE CONDITION: \(message) at \(location)")
    }

    /// Assert MainActor isolation (logs error if violated)
    func assertMainActor(_ message: String = "", file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        MainActor.assertIsolated(message)
        #else
        // In release, log instead of crash
        if !Thread.isMainThread {
            let location = "\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function)"
            logger.critical("MainActor violation: \(message) at \(location)")
        }
        #endif
    }

    // MARK: - Signal Handlers

    private func setupSignalHandlers() {
        // These signals are commonly raised by Swift runtime crashes
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

        // Re-raise signal for system crash reporter
        Darwin.signal(signal, SIG_DFL)
        Darwin.raise(signal)
    }

    /// Write crash log synchronously before app terminates
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

        try? content.write(to: fileURL, atomically: false, encoding: .utf8)

        // Also log to system log
        let logger = Logger.forCategory("CrashReporter")
        logger.critical("CRASH: \(type) - \(reason)")
    }
}
