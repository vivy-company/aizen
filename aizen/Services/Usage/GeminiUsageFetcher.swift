//
//  GeminiUsageFetcher.swift
//  aizen
//
//  Gemini OAuth usage + account data (no browser cookies)
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GeminiUsageSnapshot {
    let quotaWindows: [UsageQuotaWindow]
    let user: UsageUserIdentity?
    let errors: [String]
    let notes: [String]
}

enum GeminiUsageFetcher {
    static func fetch() async -> GeminiUsageSnapshot {
        var errors: [String] = []
        var notes: [String] = []
        var quota: [UsageQuotaWindow] = []
        var user: UsageUserIdentity?

        let authType = currentAuthType()
        switch authType {
        case .apiKey:
            errors.append("Gemini API key auth is not supported for usage.")
            return GeminiUsageSnapshot(quotaWindows: [], user: nil, errors: errors, notes: notes)
        case .vertexAI:
            errors.append("Gemini Vertex AI auth is not supported for usage.")
            return GeminiUsageSnapshot(quotaWindows: [], user: nil, errors: errors, notes: notes)
        case .oauthPersonal, .unknown:
            break
        }

        do {
            var creds = try loadCredentials()
            if let expiry = creds.expiryDate, expiry < Date() {
                guard let refreshToken = creds.refreshToken else {
                    throw GeminiStatusError.notLoggedIn
                }
                let newToken = try await refreshAccessToken(refreshToken: refreshToken)
                creds.accessToken = newToken
            }

            guard let accessToken = creds.accessToken, !accessToken.isEmpty else {
                throw GeminiStatusError.notLoggedIn
            }

            let projectId = try? await discoverProjectId(accessToken: accessToken)
            let quotaResponse = try await fetchQuota(accessToken: accessToken, projectId: projectId)
            let modelQuotas = try parseQuotaBuckets(quotaResponse)

            quota.append(contentsOf: mapQuotaWindows(from: modelQuotas))

            let claims = parseTokenClaims(creds.idToken)
            let plan = await fetchPlan(accessToken: accessToken, hostedDomain: claims.hostedDomain)
            user = UsageUserIdentity(email: claims.email, organization: claims.hostedDomain, plan: plan)

            if quota.isEmpty {
                notes.append("No Gemini subscription usage returned by the quota API.")
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        return GeminiUsageSnapshot(quotaWindows: quota, user: user, errors: errors, notes: notes)
    }
}

// MARK: - Gemini auth

private enum GeminiAuthType: String {
    case oauthPersonal = "oauth-personal"
    case apiKey = "api-key"
    case vertexAI = "vertex-ai"
    case unknown
}

private func currentAuthType(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> GeminiAuthType {
    let url = homeDirectory.appendingPathComponent(".gemini/settings.json")
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let security = json["security"] as? [String: Any],
          let auth = security["auth"] as? [String: Any],
          let selected = auth["selectedType"] as? String
    else {
        return .unknown
    }

    return GeminiAuthType(rawValue: selected) ?? .unknown
}

private struct GeminiOAuthCredentials {
    var accessToken: String?
    let idToken: String?
    let refreshToken: String?
    let expiryDate: Date?
}

private func loadCredentials(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> GeminiOAuthCredentials {
    let url = homeDirectory.appendingPathComponent(".gemini/oauth_creds.json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw GeminiStatusError.notLoggedIn
    }

    let data = try Data(contentsOf: url)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw GeminiStatusError.parseFailed("Invalid credentials file")
    }

    let accessToken = json["access_token"] as? String
    let idToken = json["id_token"] as? String
    let refreshToken = json["refresh_token"] as? String

    var expiryDate: Date?
    if let expiryMs = json["expiry_date"] as? Double {
        expiryDate = Date(timeIntervalSince1970: expiryMs / 1000)
    }

    return GeminiOAuthCredentials(
        accessToken: accessToken,
        idToken: idToken,
        refreshToken: refreshToken,
        expiryDate: expiryDate
    )
}

private enum GeminiStatusError: LocalizedError {
    case geminiNotInstalled
    case notLoggedIn
    case parseFailed(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .geminiNotInstalled:
            return "Gemini CLI is not installed or not on PATH."
        case .notLoggedIn:
            return "Not logged in to Gemini. Run 'gemini' to authenticate."
        case let .parseFailed(message):
            return "Could not parse Gemini usage: \(message)"
        case let .apiError(message):
            return "Gemini API error: \(message)"
        }
    }
}

// MARK: - Token refresh

private struct GeminiOAuthClientCredentials {
    let clientId: String
    let clientSecret: String
}

private func refreshAccessToken(
    refreshToken: String,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) async throws -> String {
    guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
        throw GeminiStatusError.apiError("Invalid token refresh URL")
    }

    guard let oauthCreds = extractOAuthCredentials() else {
        throw GeminiStatusError.apiError("Could not find Gemini CLI OAuth configuration")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let body = [
        "client_id=\(oauthCreds.clientId)",
        "client_secret=\(oauthCreds.clientSecret)",
        "refresh_token=\(refreshToken)",
        "grant_type=refresh_token",
    ].joined(separator: "&")
    request.httpBody = body.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GeminiStatusError.apiError("Invalid refresh response")
    }
    guard httpResponse.statusCode == 200 else {
        throw GeminiStatusError.notLoggedIn
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let newAccessToken = json["access_token"] as? String
    else {
        throw GeminiStatusError.parseFailed("Could not parse refresh response")
    }

    try updateStoredCredentials(json, homeDirectory: homeDirectory)
    return newAccessToken
}

private func updateStoredCredentials(_ refreshResponse: [String: Any], homeDirectory: URL) throws {
    let credsURL = homeDirectory.appendingPathComponent(".gemini/oauth_creds.json")
    guard let existing = try? Data(contentsOf: credsURL),
          var json = try? JSONSerialization.jsonObject(with: existing) as? [String: Any]
    else {
        return
    }

    if let accessToken = refreshResponse["access_token"] {
        json["access_token"] = accessToken
    }
    if let expiresIn = refreshResponse["expires_in"] as? Double {
        json["expiry_date"] = (Date().timeIntervalSince1970 + expiresIn) * 1000
    }
    if let idToken = refreshResponse["id_token"] {
        json["id_token"] = idToken
    }

    let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
    try updated.write(to: credsURL, options: .atomic)
}

private func extractOAuthCredentials() -> GeminiOAuthClientCredentials? {
    guard let geminiPath = resolveGeminiBinary() else { return nil }

    let fm = FileManager.default
    var realPath = geminiPath
    if let resolved = try? fm.destinationOfSymbolicLink(atPath: geminiPath) {
        if resolved.hasPrefix("/") {
            realPath = resolved
        } else {
            realPath = (geminiPath as NSString).deletingLastPathComponent + "/" + resolved
        }
    }

    let binDir = (realPath as NSString).deletingLastPathComponent
    let baseDir = (binDir as NSString).deletingLastPathComponent

    let oauthSubpath = "node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
    let oauthFile = "dist/src/code_assist/oauth2.js"
    let possiblePaths = [
        "\(baseDir)/libexec/lib/\(oauthSubpath)",
        "\(baseDir)/lib/\(oauthSubpath)",
        "\(baseDir)/../gemini-cli-core/\(oauthFile)",
        "\(baseDir)/node_modules/@google/gemini-cli-core/\(oauthFile)",
    ]

    for path in possiblePaths {
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            if let creds = parseOAuthCredentials(from: content) {
                return creds
            }
        }
    }

    return nil
}

private func parseOAuthCredentials(from content: String) -> GeminiOAuthClientCredentials? {
    let clientIdPattern = #"OAUTH_CLIENT_ID\s*=\s*['\"]([\w\-\.]+)['\"]\s*;"#
    let secretPattern = #"OAUTH_CLIENT_SECRET\s*=\s*['\"]([\w\-]+)['\"]\s*;"#

    guard let clientIdRegex = try? NSRegularExpression(pattern: clientIdPattern),
          let secretRegex = try? NSRegularExpression(pattern: secretPattern)
    else {
        return nil
    }

    let range = NSRange(content.startIndex..., in: content)
    guard let clientIdMatch = clientIdRegex.firstMatch(in: content, range: range),
          let secretMatch = secretRegex.firstMatch(in: content, range: range),
          let clientIdRange = Range(clientIdMatch.range(at: 1), in: content),
          let secretRange = Range(secretMatch.range(at: 1), in: content)
    else {
        return nil
    }

    return GeminiOAuthClientCredentials(
        clientId: String(content[clientIdRange]),
        clientSecret: String(content[secretRange])
    )
}

private func resolveGeminiBinary() -> String? {
    let managed = AgentRegistry.managedPath(for: "gemini")
    if FileManager.default.isExecutableFile(atPath: managed) {
        return managed
    }
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for dir in path.split(separator: ":") {
        let candidate = "\(dir)/gemini"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

// MARK: - Quota APIs

private func discoverProjectId(accessToken: String) async throws -> String? {
    guard let url = URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects") else {
        return nil
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let projects = json["projects"] as? [[String: Any]]
    else { return nil }

    for project in projects {
        guard let projectId = project["projectId"] as? String else { continue }
        if projectId.hasPrefix("gen-lang-client") { return projectId }
        if let labels = project["labels"] as? [String: String], labels["generative-language"] != nil {
            return projectId
        }
    }

    return nil
}

private func fetchQuota(accessToken: String, projectId: String?) async throws -> Data {
    guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota") else {
        throw GeminiStatusError.apiError("Invalid endpoint URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let projectId {
        request.httpBody = Data("{\"project\": \"\(projectId)\"}".utf8)
    } else {
        request.httpBody = Data("{}".utf8)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw GeminiStatusError.apiError("Invalid response")
    }
    if http.statusCode == 401 { throw GeminiStatusError.notLoggedIn }
    guard http.statusCode == 200 else {
        throw GeminiStatusError.apiError("HTTP \(http.statusCode)")
    }
    return data
}

private struct GeminiModelQuota {
    let modelId: String
    let percentLeft: Double
    let resetTime: Date?
    let resetDescription: String?
}

private struct QuotaBucket: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
    let modelId: String?
}

private struct QuotaResponse: Decodable {
    let buckets: [QuotaBucket]?
}

private func parseQuotaBuckets(_ data: Data) throws -> [GeminiModelQuota] {
    let decoder = JSONDecoder()
    let response = try decoder.decode(QuotaResponse.self, from: data)
    guard let buckets = response.buckets, !buckets.isEmpty else {
        throw GeminiStatusError.parseFailed("No quota buckets in response")
    }

    var modelQuotaMap: [String: (fraction: Double, resetString: String?)] = [:]

    for bucket in buckets {
        guard let modelId = bucket.modelId, let fraction = bucket.remainingFraction else { continue }
        if let existing = modelQuotaMap[modelId] {
            if fraction < existing.fraction {
                modelQuotaMap[modelId] = (fraction, bucket.resetTime)
            }
        } else {
            modelQuotaMap[modelId] = (fraction, bucket.resetTime)
        }
    }

    return modelQuotaMap.sorted { $0.key < $1.key }.map { modelId, info in
        let resetDate = info.resetString.flatMap(parseResetTime)
        return GeminiModelQuota(
            modelId: modelId,
            percentLeft: info.fraction * 100,
            resetTime: resetDate,
            resetDescription: info.resetString.flatMap(formatResetTime)
        )
    }
}

private func mapQuotaWindows(from quotas: [GeminiModelQuota]) -> [UsageQuotaWindow] {
    let lower = quotas.map { ($0.modelId.lowercased(), $0) }
    let flashQuotas = lower.filter { $0.0.contains("flash") }.map(\.1)
    let proQuotas = lower.filter { $0.0.contains("pro") }.map(\.1)

    var windows: [UsageQuotaWindow] = []

    if let proMin = proQuotas.min(by: { $0.percentLeft < $1.percentLeft }) {
        windows.append(makeWindow(title: "Pro models (24h)", quota: proMin))
    }
    if let flashMin = flashQuotas.min(by: { $0.percentLeft < $1.percentLeft }) {
        windows.append(makeWindow(title: "Flash models (24h)", quota: flashMin))
    }

    if windows.isEmpty, let overall = quotas.min(by: { $0.percentLeft < $1.percentLeft }) {
        windows.append(makeWindow(title: "Models (24h)", quota: overall))
    }

    return windows
}

private func makeWindow(title: String, quota: GeminiModelQuota) -> UsageQuotaWindow {
    let usedPercent = max(0, min(100, 100 - quota.percentLeft))
    return UsageQuotaWindow(
        title: title,
        usedPercent: usedPercent,
        resetsAt: quota.resetTime,
        resetDescription: quota.resetDescription
    )
}

private func parseResetTime(_ isoString: String) -> Date? {
    ISO8601DateParser.shared.parse(isoString)
}

private func formatResetTime(_ isoString: String) -> String {
    guard let resetDate = parseResetTime(isoString) else { return "Resets soon" }

    let interval = resetDate.timeIntervalSince(Date())
    if interval <= 0 { return "Resets soon" }

    let hours = Int(interval / 3600)
    let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

    if hours > 0 {
        return "Resets in \(hours)h \(minutes)m"
    }
    return "Resets in \(minutes)m"
}

// MARK: - Plan + identity

private struct GeminiTokenClaims {
    let email: String?
    let hostedDomain: String?
}

private func parseTokenClaims(_ idToken: String?) -> GeminiTokenClaims {
    guard let idToken else { return GeminiTokenClaims(email: nil, hostedDomain: nil) }

    let parts = idToken.components(separatedBy: ".")
    guard parts.count >= 2 else { return GeminiTokenClaims(email: nil, hostedDomain: nil) }

    var payload = parts[1].replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = payload.count % 4
    if remainder > 0 {
        payload += String(repeating: "=", count: 4 - remainder)
    }

    guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return GeminiTokenClaims(email: nil, hostedDomain: nil)
    }

    return GeminiTokenClaims(
        email: json["email"] as? String,
        hostedDomain: json["hd"] as? String
    )
}

private enum GeminiUserTierId: String {
    case free = "free-tier"
    case legacy = "legacy-tier"
    case standard = "standard-tier"
}

private func fetchPlan(accessToken: String, hostedDomain: String?) async -> String? {
    guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist") else {
        return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{\"metadata\":{\"ideType\":\"GEMINI_CLI\",\"pluginType\":\"GEMINI\"}}".utf8)

    guard let (data, response) = try? await URLSession.shared.data(for: request) else {
        return nil
    }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        return nil
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let currentTier = json["currentTier"] as? [String: Any],
          let tierId = currentTier["id"] as? String,
          let tier = GeminiUserTierId(rawValue: tierId)
    else {
        return nil
    }

    switch (tier, hostedDomain) {
    case (.standard, _):
        return "Paid"
    case (.free, .some):
        return "Workspace"
    case (.free, .none):
        return "Free"
    case (.legacy, _):
        return "Legacy"
    }
}
