//
//  ClaudeUsageFetcher.swift
//  aizen
//
//  Claude OAuth usage + account data (no browser cookies)
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

struct ClaudeUsageSnapshot {
    let quotaWindows: [UsageQuotaWindow]
    let user: UsageUserIdentity?
    let errors: [String]
    let notes: [String]
}

enum ClaudeUsageFetcher {
    static func fetch() async -> ClaudeUsageSnapshot {
        let errors: [String] = []
        var notes: [String] = []
        var quota: [UsageQuotaWindow] = []
        var user: UsageUserIdentity?

        // Try to load OAuth credentials, but don't fail if they're not found
        // (user might be using custom API key instead)
        do {
            let creds = try ClaudeOAuthCredentialsStore.load()
            if creds.isExpired {
                notes.append("OAuth token expired. Run 'claude' to re-authenticate for usage stats.")
            } else {
                // Credentials found and valid, fetch OAuth usage
                do {
                    let usage = try await ClaudeOAuthUsageFetcher.fetchUsage(accessToken: creds.accessToken)
                    let statsigIdentity = loadStatsigIdentity()

                    if let window = makeWindow(title: "Session (5h)", window: usage.fiveHour) {
                        quota.append(window)
                    }
                    if let window = makeWindow(title: "Weekly", window: usage.sevenDay) {
                        quota.append(window)
                    }
                    if let window = makeWindow(
                        title: "Weekly (Sonnet/Opus)",
                        window: usage.sevenDaySonnet ?? usage.sevenDayOpus
                    ) {
                        quota.append(window)
                    }

                    if let extra = usage.extraUsage, extra.isEnabled == true {
                        let used = extra.usedCredits
                        let limit = extra.monthlyLimit
                        let remaining = (used != nil && limit != nil) ? (limit! - used!) : nil
                        var usedPercent = extra.utilization
                        if usedPercent == nil, let used, let limit, limit > 0 {
                            usedPercent = (used / limit) * 100
                        }
                        let unit = (extra.currency?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                            ?? "USD"
                        quota.append(
                            UsageQuotaWindow(
                                title: "Extra usage",
                                usedPercent: usedPercent,
                                usedAmount: used,
                                remainingAmount: remaining,
                                limitAmount: limit,
                                unit: unit
                            )
                        )
                    }

                    let email = creds.email
                        ?? JWTDecoder.string(from: creds.idToken, keys: ["email"])
                        ?? JWTDecoder.string(from: creds.accessToken, keys: ["email"])
                    let organization = creds.organization
                        ?? JWTDecoder.string(from: creds.idToken, keys: ["org", "organization", "org_name"])
                        ?? statsigIdentity?.organizationID
                    let subscription = creds.subscriptionType ?? statsigIdentity?.subscriptionType
                    user = UsageUserIdentity(
                        email: email,
                        organization: organization,
                        plan: inferPlan(rateLimitTier: creds.rateLimitTier, subscriptionType: subscription)
                    )

                    if quota.isEmpty {
                        notes.append("No Claude subscription usage returned by the OAuth API.")
                    }
                    if email == nil, let accountID = statsigIdentity?.accountID {
                        notes.append("Claude account id: \(accountID)")
                    }
                } catch {
                    notes.append("Could not fetch OAuth usage: \(error.localizedDescription)")
                }
            }
        } catch let error as ClaudeOAuthCredentialsError {
            // OAuth credentials not found - this is OK if using custom API
            switch error {
            case .notFound:
                notes.append("No OAuth credentials. Using custom API key for usage is not supported.")
            case .decodeFailed, .missingAccessToken, .keychainError, .readFailed:
                notes.append("OAuth credentials issue: \(error.localizedDescription)")
            }
        } catch {
            notes.append("Unexpected error loading credentials: \(error.localizedDescription)")
        }

        return ClaudeUsageSnapshot(quotaWindows: quota, user: user, errors: errors, notes: notes)
    }

    private static func makeWindow(title: String, window: OAuthUsageWindow?) -> UsageQuotaWindow? {
        guard let window, let utilization = window.utilization else { return nil }
        let resetDate = ClaudeOAuthUsageFetcher.parseISO8601Date(window.resetsAt)
        let resetDescription = resetDate.map(UsageFormatter.resetDateString)
        return UsageQuotaWindow(
            title: title,
            usedPercent: utilization,
            resetsAt: resetDate,
            resetDescription: resetDescription
        )
    }

    private static func inferPlan(rateLimitTier: String?, subscriptionType: String?) -> String? {
        let raw = (subscriptionType ?? rateLimitTier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tier = raw.lowercased()
        if tier.contains("max") { return "Claude Max" }
        if tier.contains("pro") { return "Claude Pro" }
        if tier.contains("team") { return "Claude Team" }
        if tier.contains("enterprise") { return "Claude Enterprise" }
        if tier.contains("free") { return "Free" }
        if tier.contains("legacy") { return "Legacy" }
        return raw.isEmpty ? nil : raw
    }

    private static func loadStatsigIdentity() -> ClaudeStatsigIdentity? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statsigURL = home.appendingPathComponent(".claude/statsig")
        guard let files = try? FileManager.default.contentsOfDirectory(at: statsigURL, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }

        let candidates = files.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("statsig.failed_logs") || name.hasPrefix("statsig.cached.evaluations")
        }

        let sorted = candidates.sorted { lhs, rhs in
            let ldate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rdate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ldate > rdate
        }

        guard let latest = sorted.first,
              let data = try? Data(contentsOf: latest)
        else { return nil }

        let text = String(decoding: data.prefix(400_000), as: UTF8.self)
        let accountID = extractStatsigValue("accountUUID", in: text)
        let organizationID = extractStatsigValue("organizationUUID", in: text)
        let subscriptionType = extractStatsigValue("subscriptionType", in: text)

        if accountID == nil && organizationID == nil && subscriptionType == nil { return nil }
        return ClaudeStatsigIdentity(
            accountID: accountID,
            organizationID: organizationID,
            subscriptionType: subscriptionType
        )
    }
}

// MARK: - OAuth credentials

private struct ClaudeOAuthCredentials {
    let accessToken: String
    let expiresAt: Date?
    let rateLimitTier: String?
    let email: String?
    let organization: String?
    let idToken: String?
    let subscriptionType: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    static func parse(data: Data) throws -> ClaudeOAuthCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeOAuthCredentialsError.decodeFailed
        }
        guard let oauth = root["claudeAiOauth"] as? [String: Any] else {
            throw ClaudeOAuthCredentialsError.decodeFailed
        }

        let accessToken = (oauth["accessToken"] as? String ?? oauth["access_token"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if accessToken.isEmpty { throw ClaudeOAuthCredentialsError.missingAccessToken }

        let expiresAtMs = oauth["expiresAt"] as? Double ?? oauth["expires_at"] as? Double
        let expiresAt = expiresAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }

        let rateLimitTier = oauth["rateLimitTier"] as? String ?? oauth["rate_limit_tier"] as? String
        let idToken = oauth["idToken"] as? String ?? oauth["id_token"] as? String
        let subscriptionType = oauth["subscriptionType"] as? String ?? oauth["subscription_type"] as? String

        let email = findString(in: root, keys: ["email", "userEmail", "accountEmail", "primaryEmail"])
        let organization = findString(in: root, keys: ["organization", "org", "orgName", "team", "teamName", "company"])

        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            expiresAt: expiresAt,
            rateLimitTier: rateLimitTier,
            email: email,
            organization: organization,
            idToken: idToken,
            subscriptionType: subscriptionType
        )
    }
}

enum ClaudeOAuthCredentialsError: LocalizedError {
    case decodeFailed
    case missingAccessToken
    case notFound
    case keychainError(Int)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "Claude OAuth credentials are invalid."
        case .missingAccessToken:
            return "Claude OAuth access token missing. Run 'claude' to authenticate."
        case .notFound:
            return "Claude OAuth credentials not found. Run 'claude' to authenticate."
        case let .keychainError(status):
            return "Claude OAuth keychain error: \(status)"
        case let .readFailed(message):
            return "Claude OAuth credentials read failed: \(message)"
        }
    }
}

private enum ClaudeOAuthCredentialsStore {
    private static let credentialsPath = ".claude/.credentials.json"
    private static let keychainService = "Claude Code-credentials"

    static func load() throws -> ClaudeOAuthCredentials {
        var lastError: Error?
        if let keychainData = try? loadFromKeychain() {
            do {
                return try ClaudeOAuthCredentials.parse(data: keychainData)
            } catch {
                lastError = error
            }
        }

        do {
            let fileData = try loadFromFile()
            return try ClaudeOAuthCredentials.parse(data: fileData)
        } catch {
            if let lastError { throw lastError }
            throw error
        }
    }

    private static func loadFromFile() throws -> Data {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(credentialsPath)
        do {
            return try Data(contentsOf: url)
        } catch {
            if (error as NSError).code == NSFileReadNoSuchFileError {
                throw ClaudeOAuthCredentialsError.notFound
            }
            throw ClaudeOAuthCredentialsError.readFailed(error.localizedDescription)
        }
    }

    private static func loadFromKeychain() throws -> Data {
        #if os(macOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw ClaudeOAuthCredentialsError.readFailed("Keychain item is empty.")
            }
            if data.isEmpty { throw ClaudeOAuthCredentialsError.notFound }
            return data
        case errSecItemNotFound:
            throw ClaudeOAuthCredentialsError.notFound
        default:
            throw ClaudeOAuthCredentialsError.keychainError(Int(status))
        }
        #else
        throw ClaudeOAuthCredentialsError.notFound
        #endif
    }
}

// MARK: - OAuth usage

private enum ClaudeOAuthFetchError: LocalizedError {
    case unauthorized
    case invalidResponse
    case serverError(Int, String?)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Claude OAuth request unauthorized. Run 'claude' to re-authenticate."
        case .invalidResponse:
            return "Claude OAuth response was invalid."
        case let .serverError(code, body):
            if let body, !body.isEmpty {
                return "Claude OAuth error: HTTP \(code) - \(body)"
            }
            return "Claude OAuth error: HTTP \(code)"
        case let .networkError(error):
            return "Claude OAuth network error: \(error.localizedDescription)"
        }
    }
}

private enum ClaudeOAuthUsageFetcher {
    private static let baseURL = "https://api.anthropic.com"
    private static let usagePath = "/api/oauth/usage"
    private static let betaHeader = "oauth-2025-04-20"

    static func fetchUsage(accessToken: String) async throws -> OAuthUsageResponse {
        guard let url = URL(string: baseURL + usagePath) else {
            throw ClaudeOAuthFetchError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("aizen", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ClaudeOAuthFetchError.invalidResponse
            }
            switch http.statusCode {
            case 200:
                return try decodeUsageResponse(data)
            case 401, 403:
                throw ClaudeOAuthFetchError.unauthorized
            default:
                let body = String(data: data, encoding: .utf8)
                throw ClaudeOAuthFetchError.serverError(http.statusCode, body)
            }
        } catch let error as ClaudeOAuthFetchError {
            throw error
        } catch {
            throw ClaudeOAuthFetchError.networkError(error)
        }
    }

    static func decodeUsageResponse(_ data: Data) throws -> OAuthUsageResponse {
        let decoder = JSONDecoder()
        return try decoder.decode(OAuthUsageResponse.self, from: data)
    }

    static func parseISO8601Date(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return ISO8601DateParser.shared.parse(string)
    }
}

private func findString(in object: Any?, keys: Set<String>, depth: Int = 0) -> String? {
    guard depth <= 4 else { return nil }
    if let dict = object as? [String: Any] {
        for (key, value) in dict {
            if keys.contains(key), let str = value as? String, !str.isEmpty {
                return str
            }
            if let nested = findString(in: value, keys: keys, depth: depth + 1) { return nested }
        }
    } else if let array = object as? [Any] {
        for item in array {
            if let nested = findString(in: item, keys: keys, depth: depth + 1) { return nested }
        }
    }
    return nil
}

private struct ClaudeStatsigIdentity {
    let accountID: String?
    let organizationID: String?
    let subscriptionType: String?
}

private func extractStatsigValue(_ key: String, in text: String) -> String? {
    let needle = "\"\(key)\":\""
    guard let range = text.range(of: needle) else { return nil }
    let start = range.upperBound
    guard let end = text[start...].firstIndex(of: "\"") else { return nil }
    let value = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private struct OAuthUsageResponse: Decodable {
    let fiveHour: OAuthUsageWindow?
    let sevenDay: OAuthUsageWindow?
    let sevenDayOpus: OAuthUsageWindow?
    let sevenDaySonnet: OAuthUsageWindow?
    let extraUsage: OAuthExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

private struct OAuthUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct OAuthExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }
}
