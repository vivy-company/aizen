//
//  UsageFormatter.swift
//  aizen
//
//  Formatting helpers for usage metrics
//

import Foundation

enum UsageFormatter {
    static func tokenString(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func usdString(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func percentString(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        let clamped = max(0, min(100, value))
        return String(format: "%.0f%%", clamped)
    }

    static func relativeDateString(_ date: Date?) -> String {
        guard let date else { return "N/A" }
        return RelativeDateFormatter.shared.string(from: date)
    }

    static func amountString(_ value: Double, unit: String?) -> String {
        if unit == "USD" {
            return usdString(value)
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
