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

}
