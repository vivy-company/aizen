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
