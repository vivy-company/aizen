//
//  WorkflowRelativeTimeFormatter.swift
//  aizen
//
//  Shared relative date formatting for workflow views
//

import Foundation

enum WorkflowRelativeTimeFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
