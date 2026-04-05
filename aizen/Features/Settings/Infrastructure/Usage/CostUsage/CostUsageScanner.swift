//
//  CostUsageScanner.swift
//  aizen
//
//  Local usage log scanner for codex/claude
//

import Foundation

nonisolated enum CostUsageScanner {
    struct Options: Sendable {
        var codexSessionsRoot: URL?
        var claudeProjectsRoots: [URL]?
        var cacheRoot: URL?
        var refreshMinIntervalSeconds: TimeInterval = 60

        init(
            codexSessionsRoot: URL? = nil,
            claudeProjectsRoots: [URL]? = nil,
            cacheRoot: URL? = nil
        ) {
            self.codexSessionsRoot = codexSessionsRoot
            self.claudeProjectsRoots = claudeProjectsRoots
            self.cacheRoot = cacheRoot
        }
    }

    static func loadDailyReport(
        provider: UsageProvider,
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options()
    ) -> UsageDailyReport {
        let range = CostUsageDayRange(since: since, until: until)

        switch provider {
        case .codex:
            return self.loadCodexDaily(range: range, now: now, options: options)
        case .claude:
            return self.loadClaudeDaily(range: range, now: now, options: options)
        default:
            return UsageDailyReport(data: [], summary: nil)
        }
    }

    // MARK: - Day keys

    struct CostUsageDayRange: Sendable {
        let sinceKey: String
        let untilKey: String
        let scanSinceKey: String
        let scanUntilKey: String

        init(since: Date, until: Date) {
            self.sinceKey = Self.dayKey(from: since)
            self.untilKey = Self.dayKey(from: until)
            self.scanSinceKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: -1, to: since) ?? since)
            self.scanUntilKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: 1, to: until) ?? until)
        }

        static func dayKey(from date: Date) -> String {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            let y = comps.year ?? 1970
            let m = comps.month ?? 1
            let d = comps.day ?? 1
            return String(format: "%04d-%02d-%02d", y, m, d)
        }

        static func isInRange(dayKey: String, since: String, until: String) -> Bool {
            if dayKey < since { return false }
            if dayKey > until { return false }
            return true
        }
    }

    // MARK: - Cache helpers

    static func applyFileDays(
        cache: [String: [String: [Int]]],
        fileDays: [String: [String: [Int]]],
        sign: Int
    ) -> [String: [String: [Int]]] {
        var out = cache
        for (dayKey, models) in fileDays {
            var outModels = out[dayKey] ?? [:]
            for (model, packed) in models {
                let existing = outModels[model] ?? []
                outModels[model] = Self.mergePacked(existing, packed, sign: sign)
            }
            out[dayKey] = outModels
        }
        return out
    }

    private static func mergePacked(_ a: [Int], _ b: [Int], sign: Int) -> [Int] {
        let count = max(a.count, b.count)
        var out = Array(repeating: 0, count: count)
        for idx in 0..<count {
            let next = (a[safe: idx] ?? 0) + sign * (b[safe: idx] ?? 0)
            out[idx] = max(0, next)
        }
        return out
    }

    // MARK: - Date parsing

    static func parseDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return nil }
        guard
            let y = Int(parts[0]),
            let m = Int(parts[1]),
            let d = Int(parts[2])
        else { return nil }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        return comps.date
    }
}

extension Data {
    nonisolated func containsAscii(_ needle: String) -> Bool {
        guard let n = needle.data(using: .utf8) else { return false }
        return self.range(of: n) != nil
    }
}

extension [Int] {
    nonisolated subscript(safe index: Int) -> Int? {
        if index < 0 { return nil }
        if index >= self.count { return nil }
        return self[index]
    }
}

extension [UInt8] {
    nonisolated subscript(safe index: Int) -> UInt8? {
        if index < 0 { return nil }
        if index >= self.count { return nil }
        return self[index]
    }
}
