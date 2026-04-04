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
