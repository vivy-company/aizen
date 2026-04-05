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
        let stream = Self.makeStdoutLineStream()
        self.stdoutLineStream = stream.stream
        self.stdoutLineContinuation = stream.continuation

        try configureAndLaunchProcess(
            executable: executable,
            arguments: arguments,
            environment: environment
        )
        installReadabilityHandlers()
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
        terminateProcessIfRunning()
    }
}
