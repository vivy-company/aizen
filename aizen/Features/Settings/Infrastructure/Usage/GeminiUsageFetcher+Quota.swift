//
//  GeminiUsageFetcher+Quota.swift
//  aizen
//

import Foundation

struct GeminiModelQuota {
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

func discoverProjectId(accessToken: String) async throws -> String? {
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

func fetchQuota(accessToken: String, projectId: String?) async throws -> Data {
    guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota") else {
        throw GeminiStatusError.apiError("Invalid endpoint URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body = projectId.map { "{\"project\": \"\($0)\"}" } ?? "{}"
    request.httpBody = Data(body.utf8)

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

func parseQuotaBuckets(_ data: Data) throws -> [GeminiModelQuota] {
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

func mapQuotaWindows(from quotas: [GeminiModelQuota]) -> [UsageQuotaWindow] {
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
