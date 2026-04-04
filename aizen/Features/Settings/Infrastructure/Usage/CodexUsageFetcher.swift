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
            let shellEnv = await ShellEnvironment.loadUserShellEnvironmentAsync()
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

    static func loadAccountIdentity() -> UsageUserIdentity? {
        CodexUsageIdentityLoader.loadAccountIdentity()
    }

    static func userIdentity(from response: RPCAccountResponse) -> UsageUserIdentity? {
        CodexUsageIdentityLoader.userIdentity(from: response)
    }
}
