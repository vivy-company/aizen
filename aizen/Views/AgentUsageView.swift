//
//  AgentUsageView.swift
//  aizen
//
//  Shared UI for agent usage display
//

import Foundation
import SwiftUI

struct AgentActivityRowsView: View {
    let stats: AgentUsageStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            usageRow("Sessions", value: String(stats.sessionsStarted))
            usageRow("Prompts", value: String(stats.promptsSent))
            usageRow("Responses", value: String(stats.agentMessages))
            usageRow("Tool calls", value: String(stats.toolCalls))
            usageRow("Attachments", value: String(stats.attachmentsSent))
            usageRow("Last used", value: lastUsedText)
        }
    }

    private var lastUsedText: String {
        guard let lastUsedAt = stats.lastUsedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsedAt, relativeTo: Date())
    }

    private func usageRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

struct AgentUsageSummaryView: View {
    let report: AgentUsageReport
    let refreshState: UsageRefreshState
    let onRefresh: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Usage summary")
                    .font(.headline)
                Spacer()
                refreshButton
            }

            if report.periods.isEmpty {
                Text("No usage data yet.")
                    .foregroundStyle(.secondary)
            } else {
                periodSummaryGrid(periods: report.periods)
            }

            if let quota = report.quota.first {
                UsageProgressRow(
                    title: "Subscription",
                    subtitle: quota.resetDescription,
                    value: quota.usedPercent
                )
            }

            if let user = report.user, hasAccountDetails(user) {
                Text(user.email ?? user.organization ?? "Signed in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = report.unavailableReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("View details") {
                    onOpenDetails()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        switch refreshState {
        case .loading:
            ProgressView()
                .controlSize(.small)
        default:
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh usage")
        }
    }

    private func periodSummaryGrid(periods: [UsagePeriodSummary]) -> some View {
        let totals = periods.map { Double($0.totalTokens ?? 0) }
        let maxTotal = max(totals.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(periods, id: \.label) { period in
                let total = Double(period.totalTokens ?? 0)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(period.label)
                        Spacer()
                        Text(UsageFormatter.usdString(period.costUSD))
                            .foregroundStyle(.secondary)
                    }
                    UsageProgressBar(value: total, maxValue: maxTotal)
                    Text("Total tokens \(UsageFormatter.tokenString(period.totalTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hasAccountDetails(_ user: UsageUserIdentity) -> Bool {
        user.email != nil || user.organization != nil || user.plan != nil
    }
}

struct AgentUsageDetailContent: View {
    let report: AgentUsageReport
    let refreshState: UsageRefreshState
    let activityStats: AgentUsageStats
    let onRefresh: () -> Void
    let showActivity: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow

            if let reason = report.unavailableReason {
                Text(reason)
                    .foregroundStyle(.secondary)
            }

            usageCard(
                title: "Tokens & cost",
                subtitle: "Today, last 30 days, and this month",
                accent: Color(red: 0.12, green: 0.5, blue: 0.9)
            ) {
                if report.periods.isEmpty {
                    Text("No token usage available.")
                        .foregroundStyle(.secondary)
                } else {
                    tokenDetailChart(periods: report.periods)
                }
            }

            usageCard(
                title: "Subscription usage",
                subtitle: report.quota.isEmpty ? "No subscription data yet" : "Active limits and resets",
                accent: Color(red: 0.2, green: 0.6, blue: 0.35)
            ) {
                if report.quota.isEmpty {
                    Text("No subscription data available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.quota) { window in
                        UsageQuotaRow(window: window)
                    }
                }
            }

            usageCard(
                title: "Current user",
                subtitle: nil,
                accent: Color(red: 0.95, green: 0.55, blue: 0.2)
            ) {
                if let user = report.user, hasAccountDetails(user) {
                    usageInfoRow("Email", value: user.email ?? "N/A")
                    usageInfoRow("Organization", value: user.organization ?? "N/A")
                    usageInfoRow("Plan", value: user.plan ?? "N/A")
                } else {
                    Text("No user details available.")
                        .foregroundStyle(.secondary)
                }
            }

            if showActivity {
                usageCard(
                    title: "Activity",
                    subtitle: "Local usage signals",
                    accent: Color(red: 0.62, green: 0.6, blue: 0.2)
                ) {
                    AgentActivityRowsView(stats: activityStats)
                }
            }

            if !report.notes.isEmpty {
                usageCard(
                    title: "Notes",
                    subtitle: nil,
                    accent: Color.secondary
                ) {
                    ForEach(report.notes, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !report.errors.isEmpty {
                usageCard(
                    title: "Errors",
                    subtitle: nil,
                    accent: Color.red
                ) {
                    ForEach(report.errors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Last updated")
            Spacer()
            Text(UsageFormatter.relativeDateString(report.updatedAt))
                .foregroundStyle(.secondary)
            refreshButton
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        switch refreshState {
        case .loading:
            ProgressView()
                .controlSize(.small)
        default:
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh usage")
        }
    }

    private func usageCard(
        title: String,
        subtitle: String?,
        accent: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    accent.opacity(0.12),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func usageInfoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func tokenDetailChart(periods: [UsagePeriodSummary]) -> some View {
        let totals = periods.map { Double($0.totalTokens ?? 0) }
        let maxTotal = max(totals.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(periods, id: \.label) { period in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(period.label)
                        Spacer()
                        Text(UsageFormatter.usdString(period.costUSD))
                            .foregroundStyle(.secondary)
                    }
                    UsageStackedBar(
                        input: Double(period.inputTokens ?? 0),
                        output: Double(period.outputTokens ?? 0),
                        total: maxTotal
                    )
                    Text(tokenLine(for: period))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func tokenLine(for period: UsagePeriodSummary) -> String {
        let input = UsageFormatter.tokenString(period.inputTokens)
        let output = UsageFormatter.tokenString(period.outputTokens)
        let total = UsageFormatter.tokenString(period.totalTokens)
        return "Input \(input) | Output \(output) | Total \(total)"
    }

    private func amountString(_ value: Double, unit: String?) -> String {
        if unit == "USD" {
            return UsageFormatter.usdString(value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let base = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        if let unit, !unit.isEmpty {
            return "\(base) \(unit)"
        }
        return base
    }

    private func absoluteDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func hasAccountDetails(_ user: UsageUserIdentity) -> Bool {
        user.email != nil || user.organization != nil || user.plan != nil
    }
}

struct UsageProgressRow: View {
    let title: String
    let subtitle: String?
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if let value {
                    Text(UsageFormatter.percentString(value))
                        .foregroundStyle(.secondary)
                }
            }
            UsageProgressBar(value: value ?? 0, maxValue: 100)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UsageProgressBar: View {
    let value: Double
    let maxValue: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = maxValue > 0 ? min(1, value / maxValue) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: width * fraction)
            }
        }
        .frame(height: 6)
    }
}

struct UsageStackedBar: View {
    let input: Double
    let output: Double
    let total: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let totalTokens = max(total, 1)
            let inputWidth = width * min(1, input / totalTokens)
            let outputWidth = width * min(1, output / totalTokens)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: inputWidth)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: min(width, inputWidth + outputWidth))
            }
        }
        .frame(height: 8)
    }
}

struct UsageStatTile: View {
    let title: String
    let primary: String
    let secondary: String
    let value: Double
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(primary)
                .font(.title3)
                .fontWeight(.semibold)
            UsageProgressBar(value: value, maxValue: maxValue)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct UsageQuotaRow: View {
    let window: UsageQuotaWindow

    var body: some View {
        HStack(spacing: 12) {
            UsageRing(percent: window.usedPercent)
            VStack(alignment: .leading, spacing: 4) {
                Text(window.title)
                    .font(.subheadline)
                if let detail = detailText {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var detailText: String? {
        var parts: [String] = []
        if let remaining = window.remainingAmount {
            parts.append("Remaining \(amountString(remaining, unit: window.unit))")
        }
        if let used = window.usedAmount {
            parts.append("Used \(amountString(used, unit: window.unit))")
        }
        if let limit = window.limitAmount {
            parts.append("Limit \(amountString(limit, unit: window.unit))")
        }
        if let reset = window.resetDescription {
            parts.append("Resets \(reset)")
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " | ")
    }

    private func amountString(_ value: Double, unit: String?) -> String {
        if unit == "USD" {
            return UsageFormatter.usdString(value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let base = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        if let unit, !unit.isEmpty {
            return "\(base) \(unit)"
        }
        return base
    }
}

struct UsageRing: View {
    let percent: Double?

    var body: some View {
        let pct = percent ?? 0
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(1, pct / 100))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(UsageFormatter.percentString(percent))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
    }
}

struct AgentUsageSheet: View {
    let agentId: String
    let agentName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var metricsStore = AgentUsageMetricsStore.shared
    @ObservedObject private var activityStore = AgentUsageStore.shared

    var body: some View {
        let report = metricsStore.report(for: agentId)
        let refreshState = metricsStore.refreshState(for: agentId)

        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    AgentIconView(agent: agentId, size: 28)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agentName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Usage details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                DetailCloseButton { dismiss() }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    AgentUsageDetailContent(
                        report: report,
                        refreshState: refreshState,
                        activityStats: activityStore.stats(for: agentId),
                        onRefresh: { metricsStore.refresh(agentId: agentId, force: true) },
                        showActivity: true
                    )
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: .infinity, alignment: .leading)
        .onAppear {
            metricsStore.refreshIfNeeded(agentId: agentId)
        }
    }
}
