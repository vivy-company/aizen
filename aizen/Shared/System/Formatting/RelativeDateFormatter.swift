//
//  RelativeDateFormatter.swift
//  aizen
//
//  Shared relative date formatting
//

import Foundation

// SAFETY: Thread-safe via NSLock protecting all formatter access.
// RelativeDateTimeFormatter is not Sendable but access is serialized.
nonisolated final class RelativeDateFormatter: @unchecked Sendable {
    static let shared = RelativeDateFormatter()

    private let formatter: RelativeDateTimeFormatter
    private let lock = NSLock()

    private init() {
        formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
    }

    func string(from date: Date) -> String {
        lock.lock()
        let value = formatter.localizedString(for: date, relativeTo: Date())
        lock.unlock()
        return value
    }
}
