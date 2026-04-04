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
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutLineStream: AsyncStream<Data>
    private let stdoutLineContinuation: AsyncStream<Data>.Continuation
    private var nextID = 1
    private let stderrLock = NSLock()
    private var stderrLines: [String] = []
    private let stderrLimit = 6

    // SAFETY: Thread-safe via NSLock protecting buffer mutations.
    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func appendAndDrainLines(_ data: Data) -> [Data] {
            self.lock.lock()
            defer { self.lock.unlock() }

            self.buffer.append(data)
            var out: [Data] = []
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let lineData = Data(self.buffer[..<newline])
                self.buffer.removeSubrange(...newline)
                if !lineData.isEmpty {
                    out.append(lineData)
                }
            }
            return out
        }
    }

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

    private func request(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let id = self.nextID
        self.nextID += 1
        try self.sendRequest(id: id, method: method, params: params)

        while true {
            let message = try await self.readNextMessage()

            if message["id"] == nil, message["method"] != nil {
                continue
            }

            guard let messageID = self.jsonID(message["id"]), messageID == id else { continue }

            if let error = message["error"] as? [String: Any], let messageText = error["message"] as? String {
                throw RPCWireError.requestFailed(messageText)
            }

            return message
        }
    }

    private func sendNotification(method: String, params: [String: Any]? = nil) throws {
        try self.sendMessage([
            "method": method,
            "params": params ?? [:],
        ])
    }

    private func sendRequest(id: Int, method: String, params: [String: Any]? = nil) throws {
        try self.sendMessage([
            "id": id,
            "method": method,
            "params": params ?? [:],
        ])
    }

    private func sendMessage(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        var buffer = data
        buffer.append(0x0A)
        try self.stdinPipe.fileHandleForWriting.write(contentsOf: buffer)
    }

    private func readNextMessage() async throws -> [String: Any] {
        for await line in stdoutLineStream {
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                return obj
            }
        }
        if let summary = stderrSummary() {
            throw RPCWireError.malformed("codex app-server closed stdout. \(summary)")
        }
        throw RPCWireError.malformed("codex app-server closed stdout")
    }

    private func jsonID(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String, let number = Int(string) { return number }
        return nil
    }

    private func decodeResult<T: Decodable>(from message: [String: Any], as type: T.Type) throws -> T {
        guard let result = message["result"] else {
            throw RPCWireError.malformed("Missing result")
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func recordStderr(_ line: String) {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stderrLines.append(trimmed)
        if stderrLines.count > stderrLimit {
            stderrLines.removeFirst(stderrLines.count - stderrLimit)
        }
    }

    private func stderrSummary() -> String? {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        guard !stderrLines.isEmpty else { return nil }
        return "stderr: " + stderrLines.joined(separator: " | ")
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
