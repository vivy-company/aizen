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
        return RelativeDateFormatter.shared.string(from: lastUsedAt)
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

    private let gridSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            if let reason = report.unavailableReason {
                Text(reason)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }

            // Top row: Hero stats
            HStack(spacing: gridSpacing) {
                heroStatCard(
                    icon: "bolt.fill",
                    iconColor: .purple,
                    value: totalCostString,
                    label: "Total cost",
                    sublabel: "This month"
                )
                heroStatCard(
                    icon: "text.word.spacing",
                    iconColor: .blue,
                    value: totalTokensString,
                    label: "Tokens",
                    sublabel: "This month"
                )
                if let primaryQuota = report.quota.first {
                    heroStatCard(
                        icon: "gauge.with.dots.needle.50percent",
                        iconColor: quotaColor(primaryQuota.usedPercent),
                        value: UsageFormatter.percentString(primaryQuota.usedPercent),
                        label: primaryQuota.title,
                        sublabel: primaryQuota.resetDescription
                    )
                } else {
                    heroStatCard(
                        icon: "gauge.with.dots.needle.50percent",
                        iconColor: .secondary,
                        value: "N/A",
                        label: "Usage",
                        sublabel: nil
                    )
                }
            }

            // Second row: Activity stats grid + Plan card
            HStack(alignment: .top, spacing: gridSpacing) {
                // Activity mini-grid (2x3)
                if showActivity {
                    VStack(spacing: gridSpacing) {
                        HStack(spacing: gridSpacing) {
                            miniStatCard(
                                value: "\(activityStats.sessionsStarted)",
                                label: "Sessions",
                                icon: "bubble.left.and.bubble.right.fill",
                                color: .green
                            )
                            miniStatCard(
                                value: "\(activityStats.promptsSent)",
                                label: "Prompts",
                                icon: "arrow.up.circle.fill",
                                color: .blue
                            )
                        }
                        HStack(spacing: gridSpacing) {
                            miniStatCard(
                                value: "\(activityStats.agentMessages)",
                                label: "Responses",
                                icon: "arrow.down.circle.fill",
                                color: .indigo
                            )
                            miniStatCard(
                                value: "\(activityStats.toolCalls)",
                                label: "Tool calls",
                                icon: "wrench.and.screwdriver.fill",
                                color: .orange
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Plan & user card
                VStack(alignment: .leading, spacing: 8) {
                    if let user = report.user, hasAccountDetails(user) {
                        planCard(user: user)
                    } else {
                        bentoCard(minHeight: 130) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Account", systemImage: "person.crop.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Not signed in")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Third row: Token breakdown + Quota rings
            HStack(alignment: .top, spacing: gridSpacing) {
                // Token periods
                bentoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Token usage", systemImage: "chart.bar.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        if report.periods.isEmpty {
                            Spacer()
                            Text("No data")
                                .foregroundStyle(.tertiary)
                            Spacer()
                        } else {
                            tokenPeriodsList
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                // Quota rings column - match height of token card
                if report.quota.count > 1 {
                    VStack(spacing: gridSpacing) {
                        ForEach(report.quota.dropFirst()) { window in
                            quotaRingCard(window: window)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 200, maxHeight: .infinity)
                } else {
                    // Last used card
                    bentoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Last active", systemImage: "clock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastUsedText)
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 200)
                }
            }
            .frame(minHeight: 180)

            // Footer row: Notes, Errors, Last updated
            HStack(alignment: .top, spacing: gridSpacing) {
                if !report.notes.isEmpty || !report.errors.isEmpty {
                    bentoCard(maxHeight: .infinity) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !report.notes.isEmpty {
                                ForEach(report.notes, id: \.self) { note in
                                    Label(note, systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if !report.errors.isEmpty {
                                ForEach(report.errors, id: \.self) { error in
                                    Label(error, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                // Refresh card
                bentoCard(maxHeight: .infinity) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text(UsageFormatter.relativeDateString(report.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        refreshButton
                    }
                }
                .frame(minWidth: 200)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Computed Properties

    private var totalCostString: String {
        guard let month = report.periods.first(where: { $0.label.lowercased().contains("month") }) else {
            if let first = report.periods.first {
                return UsageFormatter.usdString(first.costUSD)
            }
            return "$0"
        }
        return UsageFormatter.usdString(month.costUSD)
    }

    private var totalTokensString: String {
        guard let month = report.periods.first(where: { $0.label.lowercased().contains("month") }) else {
            if let first = report.periods.first {
                return UsageFormatter.tokenString(first.totalTokens)
            }
            return "0"
        }
        return UsageFormatter.tokenString(month.totalTokens)
    }

    private var lastUsedText: String {
        guard let lastUsedAt = activityStats.lastUsedAt else { return "Never" }
        return RelativeDateFormatter.shared.string(from: lastUsedAt)
    }

    private var tokenPeriodsList: some View {
        let totals = report.periods.map { Double($0.totalTokens ?? 0) }
        let maxTotal = max(totals.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(report.periods, id: \.label) { period in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(period.label)
                            .font(.caption)
                        Spacer()
                        Text(UsageFormatter.usdString(period.costUSD))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    UsageStackedBar(
                        input: Double(period.inputTokens ?? 0),
                        output: Double(period.outputTokens ?? 0),
                        total: maxTotal
                    )
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text("In \(UsageFormatter.tokenString(period.inputTokens))")
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                            Text("Out \(UsageFormatter.tokenString(period.outputTokens))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Card Components

    private func heroStatCard(
        icon: String,
        iconColor: Color,
        value: String,
        label: String,
        sublabel: String?
    ) -> some View {
        bentoCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)

                Spacer()

                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                    if let sublabel {
                        Text(sublabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120)
    }

    private func miniStatCard(
        value: String,
        label: String,
        icon: String,
        color: Color
    ) -> some View {
        bentoCard {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .fontDesign(.rounded)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .frame(minWidth: 120)
    }

    private func planCard(user: UsageUserIdentity) -> some View {
        bentoCard(minHeight: 130) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Account", systemImage: "person.crop.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let plan = user.plan {
                    Text(plan)
                        .font(.title3)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let email = user.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let org = user.organization {
                        Text(org)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quotaRingCard(window: UsageQuotaWindow) -> some View {
        bentoCard(maxHeight: .infinity) {
            HStack(spacing: 12) {
                UsageRing(percent: window.usedPercent)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let reset = window.resetDescription {
                        Text(reset)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
    }

    private func bentoCard<Content: View>(
        minHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: maxHeight, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
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

    // MARK: - Helpers

    private func quotaColor(_ percent: Double?) -> Color {
        guard let p = percent else { return .secondary }
        if p >= 90 { return .red }
        if p >= 70 { return .orange }
        return .green
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
            parts.append("Remaining \(UsageFormatter.amountString(remaining, unit: window.unit))")
        }
        if let used = window.usedAmount {
            parts.append("Used \(UsageFormatter.amountString(used, unit: window.unit))")
        }
        if let limit = window.limitAmount {
            parts.append("Limit \(UsageFormatter.amountString(limit, unit: window.unit))")
        }
        if let reset = window.resetDescription {
            parts.append("Resets \(reset)")
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " | ")
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
        .frame(minWidth: 680, maxWidth: .infinity, alignment: .leading)
        .onAppear {
            metricsStore.refreshIfNeeded(agentId: agentId)
        }
    }
}
