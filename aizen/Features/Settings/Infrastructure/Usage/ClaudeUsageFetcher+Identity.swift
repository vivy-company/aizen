import Foundation

struct ClaudeStatsigIdentity {
    let accountID: String?
    let organizationID: String?
    let subscriptionType: String?
}

func extractStatsigValue(_ key: String, in text: String) -> String? {
    let needle = "\"\(key)\":\""
    guard let range = text.range(of: needle) else { return nil }
    let start = range.upperBound
    guard let end = text[start...].firstIndex(of: "\"") else { return nil }
    let value = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

extension ClaudeUsageFetcher {
    static func inferPlan(rateLimitTier: String?, subscriptionType: String?) -> String? {
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

    static func loadStatsigIdentity() -> ClaudeStatsigIdentity? {
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
