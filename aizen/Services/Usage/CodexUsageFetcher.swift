//
//  CodexUsageFetcher.swift
//  aizen
//
//  Codex usage + account data (no browser cookies)
//

import Foundation

struct CodexUsageSnapshot {
    let quotaWindows: [UsageQuotaWindow]
    let creditsRemaining: Double?
    let user: UsageUserIdentity?
    let errors: [String]
}

enum CodexUsageFetcher {
    static func fetch() async -> CodexUsageSnapshot {
        var errors: [String] = []
        var quota: [UsageQuotaWindow] = []
        var creditsRemaining: Double?

        do {
            let shellEnv = await ShellEnvironmentLoader.shared.loadShellEnvironment()
            let rpc = try CodexRPCClient(environment: shellEnv)
            defer { rpc.shutdown() }
            try await rpc.initialize(clientName: "aizen", clientVersion: "1.0")
            let limits = try await rpc.fetchRateLimits()
            let account = try? await rpc.fetchAccount()
            if let primary = limits.primary {
                quota.append(
                    UsageQuotaWindow(
                        title: "Session (5h)",
                        usedPercent: primary.usedPercent,
                        resetsAt: primary.resetsAt,
                        resetDescription: primary.resetDescription
                    )
                )
            }
            if let secondary = limits.secondary {
                quota.append(
                    UsageQuotaWindow(
                        title: "Weekly",
                        usedPercent: secondary.usedPercent,
                        resetsAt: secondary.resetsAt,
                        resetDescription: secondary.resetDescription
                    )
                )
            }
            if let credits = limits.credits {
                creditsRemaining = credits.balance
            }

            if let account {
                let user = userIdentity(from: account)
                return CodexUsageSnapshot(
                    quotaWindows: quota,
                    creditsRemaining: creditsRemaining,
                    user: user ?? loadAccountIdentity(),
                    errors: errors
                )
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        let user = loadAccountIdentity()
        return CodexUsageSnapshot(
            quotaWindows: quota,
            creditsRemaining: creditsRemaining,
            user: user,
            errors: errors
        )
    }

    private static func loadAccountIdentity() -> UsageUserIdentity? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(home.path)/.codex")
            .appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let idToken = auth.tokens?.idToken,
              let payload = JWTDecoder.payload(from: idToken)
        else {
            return nil
        }

        let authDict = payload["https://api.openai.com/auth"] as? [String: Any]
        let profileDict = payload["https://api.openai.com/profile"] as? [String: Any]

        let plan = (authDict?["chatgpt_plan_type"] as? String)
            ?? (payload["chatgpt_plan_type"] as? String)
        let email = (payload["email"] as? String)
            ?? (profileDict?["email"] as? String)
        let organization = resolveOrganizationName(authDict: authDict, profileDict: profileDict)

        return UsageUserIdentity(email: email, organization: organization, plan: plan)
    }

    private static func resolveOrganizationName(
        authDict: [String: Any]?,
        profileDict: [String: Any]?
    ) -> String? {
        if let orgName = authDict?["org_name"] as? String { return orgName }
        if let orgId = authDict?["org_id"] as? String { return orgId }
        if let orgName = profileDict?["organization"] as? String { return orgName }
        if let orgName = profileDict?["org_name"] as? String { return orgName }

        if let orgs = authDict?["organizations"] as? [[String: Any]] {
            if let defaultOrg = orgs.first(where: { ($0["is_default"] as? Bool) == true }) {
                if let title = defaultOrg["title"] as? String { return title }
                if let orgId = defaultOrg["id"] as? String { return orgId }
            }
            if let first = orgs.first {
                if let title = first["title"] as? String { return title }
                if let orgId = first["id"] as? String { return orgId }
            }
        }

        return nil
    }

    private static func userIdentity(from response: RPCAccountResponse) -> UsageUserIdentity? {
        guard let account = response.account else { return nil }
        switch account {
        case .apiKey:
            return nil
        case let .chatgpt(email, planType):
            let cleanEmail = email.isEmpty ? nil : email
            let cleanPlan = planType.isEmpty ? nil : planType
            return UsageUserIdentity(email: cleanEmail, organization: nil, plan: cleanPlan)
        }
    }
}

// MARK: - Codex RPC

private struct RPCAccountResponse: Decodable {
    let account: RPCAccountDetails?
    let requiresOpenaiAuth: Bool?
}

private enum RPCAccountDetails: Decodable {
    case apiKey
    case chatgpt(email: String, planType: String)

    enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type.lowercased() {
        case "apikey":
            self = .apiKey
        case "chatgpt":
            let email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
            let plan = try container.decodeIfPresent(String.self, forKey: .planType) ?? ""
            self = .chatgpt(email: email, planType: plan)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown account type \(type)")
        }
    }
}

private struct RPCRateLimitsResponse: Decodable {
    let rateLimits: RPCRateLimitSnapshot
}

private struct RPCRateLimitSnapshot: Decodable {
    let primary: RPCRateLimitWindow?
    let secondary: RPCRateLimitWindow?
    let credits: RPCCreditsSnapshot?
}

private struct RPCRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?
}

private struct RPCCreditsSnapshot: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

private enum RPCWireError: Error, CustomStringConvertible, LocalizedError {
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

private final class CodexRPCClient: @unchecked Sendable {
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
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stdoutLineContinuation.finish()
                return
            }

            let lines = stdoutBuffer.appendAndDrainLines(data)
            for lineData in lines {
                stdoutLineContinuation.yield(lineData)
            }
        }

        let stderrHandle = self.stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                self.recordStderr(String(line))
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

    // MARK: - JSON-RPC helpers

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
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String, let n = Int(s) { return n }
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

private struct AuthFile: Decodable {
    struct Tokens: Decodable {
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case idTokenSnake = "id_token"
            case idTokenCamel = "idToken"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.idToken = try container.decodeIfPresent(String.self, forKey: .idTokenSnake)
                ?? container.decodeIfPresent(String.self, forKey: .idTokenCamel)
        }
    }
    let tokens: Tokens?
}

private struct RateLimitsSnapshot {
    let primary: RateWindow?
    let secondary: RateWindow?
    let credits: CreditsSnapshot?

    init(from snapshot: RPCRateLimitSnapshot) {
        self.primary = RateWindow(from: snapshot.primary)
        self.secondary = RateWindow(from: snapshot.secondary)
        self.credits = CreditsSnapshot(from: snapshot.credits)
    }
}

private struct RateWindow {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?

    init?(from rpc: RPCRateLimitWindow?) {
        guard let rpc else { return nil }
        let resetsAt = rpc.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        self.usedPercent = rpc.usedPercent
        self.windowMinutes = rpc.windowDurationMins
        self.resetsAt = resetsAt
        self.resetDescription = resetsAt.map { Self.resetDescription(from: $0) }
    }

    private static func resetDescription(from date: Date) -> String {
        UsageFormatter.resetDateString(date)
    }
}

private struct CreditsSnapshot {
    let balance: Double?

    init?(from rpc: RPCCreditsSnapshot?) {
        guard let rpc else { return nil }
        if let balance = rpc.balance, let val = Double(balance) {
            self.balance = val
        } else {
            self.balance = nil
        }
    }
}

private func resolveCodexBinary(executable: String, environment: [String: String]?) -> String? {
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

private func mergedPATH(primary: String?, secondary: String?, extras: [String]) -> String {
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
