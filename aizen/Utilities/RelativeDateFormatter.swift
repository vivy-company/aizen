//
//  RelativeDateFormatter.swift
//  aizen
//
//  Shared relative date formatting
//

import Foundation

final class RelativeDateFormatter {
    static let shared = RelativeDateFormatter()

    private let formatter: RelativeDateTimeFormatter

    private init() {
        formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
    }

    func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
