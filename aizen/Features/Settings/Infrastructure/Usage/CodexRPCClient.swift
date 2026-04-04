//
//  CodexRPCClient.swift
//  aizen
//
//  JSON-RPC client for codex app-server usage/account data
//

import Foundation

enum RPCWireError: Error, CustomStringConvertible, LocalizedError {
    case startFailed(String)
    case requestFailed(String)
    case malformed(String)

    var description: String {
        switch self {
        case let .startFailed(message):
            "Failed to start codex app-server: \(message)"
        case let .requestFailed(message):
            "RPC request failed: \(message)"
        case let .malformed(message):
            "Malformed response: \(message)"
        }
    }

    var errorDescription: String? {
        description
    }
}

// SAFETY: Process and pipes are only accessed during setup before async operations begin.
// stderrLines is protected by stderrLock. nextID is only accessed sequentially.
final class CodexRPCClient: @unchecked Sendable {
    let process = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdoutLineStream: AsyncStream<Data>
    let stdoutLineContinuation: AsyncStream<Data>.Continuation
    var nextID = 1
    let stderrLock = NSLock()
    var stderrLines: [String] = []
    let stderrLimit = 6

    init(
        executable: String = "codex",
        arguments: [String] = ["-s", "read-only", "-a", "untrusted", "app-server"],
        environment: [String: String]? = nil
    ) throws {
        var stdoutContinuation: AsyncStream<Data>.Continuation!
        self.stdoutLineStream = AsyncStream<Data> { continuation in
            stdoutContinuation = continuation
        }
        self.stdoutLineContinuation = stdoutContinuation

        let resolvedExec = resolveCodexBinary(executable: executable, environment: environment)
        guard let resolvedExec else {
            throw RPCWireError.startFailed("Codex CLI not found. Install the codex agent and retry.")
        }

        var env = environment ?? ProcessInfo.processInfo.environment
        env["PATH"] = mergedPATH(
            primary: env["PATH"],
            secondary: ProcessInfo.processInfo.environment["PATH"],
            extras: ["/opt/homebrew/bin", "/usr/local/bin"]
        )

        self.process.environment = env
        self.process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        self.process.arguments = [resolvedExec] + arguments
        self.process.standardInput = self.stdinPipe
        self.process.standardOutput = self.stdoutPipe
        self.process.standardError = self.stderrPipe

        do {
            try self.process.run()
        } catch {
            throw RPCWireError.startFailed(error.localizedDescription)
        }

        let stdoutHandle = self.stdoutPipe.fileHandleForReading
        let stdoutLineContinuation = self.stdoutLineContinuation
        let stdoutBuffer = LineBuffer()
        stdoutHandle.readabilityHandler = { handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    stdoutLineContinuation.finish()
                    return
                }
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    stdoutLineContinuation.finish()
                    return
                }

                let lines = stdoutBuffer.appendAndDrainLines(data)
                for lineData in lines {
                    stdoutLineContinuation.yield(lineData)
                }
            } catch {
                handle.readabilityHandler = nil
                stdoutLineContinuation.finish()
            }
        }

        let stderrHandle = self.stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                for line in text.split(whereSeparator: \.isNewline) {
                    self.recordStderr(String(line))
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }
    }

    func initialize(clientName: String, clientVersion: String) async throws {
        _ = try await self.request(
            method: "initialize",
            params: ["clientInfo": ["name": clientName, "version": clientVersion]]
        )
        try self.sendNotification(method: "initialized")
    }

    func fetchRateLimits() async throws -> RateLimitsSnapshot {
        let message = try await self.request(method: "account/rateLimits/read")
        let response = try self.decodeResult(from: message, as: RPCRateLimitsResponse.self)
        return RateLimitsSnapshot(from: response.rateLimits)
    }

    func fetchAccount() async throws -> RPCAccountResponse {
        let message = try await self.request(method: "account/read")
        return try self.decodeResult(from: message, as: RPCAccountResponse.self)
    }

    func shutdown() {
        if self.process.isRunning {
            self.process.terminate()
        }
    }
}

func resolveCodexBinary(executable: String, environment: [String: String]?) -> String? {
    let env = environment ?? ProcessInfo.processInfo.environment
    if let override = env["CODEX_CLI_PATH"], FileManager.default.isExecutableFile(atPath: override) {
        return override
    }
    let merged = mergedPATH(
        primary: env["PATH"],
        secondary: ProcessInfo.processInfo.environment["PATH"],
        extras: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    )
    for dir in merged.split(separator: ":") {
        let candidate = "\(dir)/\(executable)"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

func mergedPATH(primary: String?, secondary: String?, extras: [String]) -> String {
    var parts: [String] = []
    if let primary, !primary.isEmpty {
        parts.append(contentsOf: primary.split(separator: ":").map(String.init))
    }
    if let secondary, !secondary.isEmpty {
        parts.append(contentsOf: secondary.split(separator: ":").map(String.init))
    }
    parts.append(contentsOf: extras)

    if parts.isEmpty {
        parts = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    var seen = Set<String>()
    let deduped = parts.compactMap { part -> String? in
        guard !part.isEmpty else { return nil }
        if seen.insert(part).inserted {
            return part
        }
        return nil
    }
    return deduped.joined(separator: ":")
}
