//
//  UsageTokenCostCalculator.swift
//  aizen
//
//  Helpers to build period summaries from daily reports
//

import Foundation

enum UsageTokenCostCalculator {
    static func periodSummaries(
        from report: UsageDailyReport,
        monthReport: UsageDailyReport? = nil,
        now: Date = Date()
    ) -> [UsagePeriodSummary] {
        let todayKey = dayKey(from: now)
        let monthKey = monthPrefix(from: now)

        let today = report.data.first(where: { $0.date == todayKey })
        let monthSource = monthReport?.data ?? report.data
        let monthEntries = monthSource.filter { $0.date.hasPrefix(monthKey) }

        let todaySummary = UsagePeriodSummary(
            label: "Today",
            inputTokens: today?.inputTokens,
            outputTokens: today?.outputTokens,
            totalTokens: today?.totalTokens,
            costUSD: today?.costUSD
        )

        let last30Summary = UsagePeriodSummary(
            label: "Last 30 days",
            inputTokens: report.summary?.totalInputTokens,
            outputTokens: report.summary?.totalOutputTokens,
            totalTokens: report.summary?.totalTokens,
            costUSD: report.summary?.totalCostUSD
        )

        let monthSummary = aggregate(entries: monthEntries, label: "This month")

        return [todaySummary, last30Summary, monthSummary]
    }

    private static func aggregate(entries: [UsageDailyReport.Entry], label: String) -> UsagePeriodSummary {
        if entries.isEmpty {
            return UsagePeriodSummary(label: label)
        }
        let input = entries.compactMap(\.inputTokens).reduce(0, +)
        let output = entries.compactMap(\.outputTokens).reduce(0, +)
        let total = entries.compactMap(\.totalTokens).reduce(0, +)
        let cost = entries.compactMap(\.costUSD).reduce(0, +)
        let hasCost = entries.contains { $0.costUSD != nil }
        return UsagePeriodSummary(
            label: label,
            inputTokens: input,
            outputTokens: output,
            totalTokens: total,
            costUSD: hasCost ? cost : nil
        )
    }

    private static func dayKey(from date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func monthPrefix(from date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        return String(format: "%04d-%02d", y, m)
    }
}
