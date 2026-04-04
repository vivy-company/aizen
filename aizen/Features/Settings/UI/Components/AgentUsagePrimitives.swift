//
//  AgentUsagePrimitives.swift
//  aizen
//
//  Created by OpenAI Codex on 04.04.26.
//

import ACP
import Foundation
import SwiftUI

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
