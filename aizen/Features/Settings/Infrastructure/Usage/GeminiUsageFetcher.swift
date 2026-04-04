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
