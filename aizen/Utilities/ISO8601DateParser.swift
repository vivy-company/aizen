//
//  ISO8601DateParser.swift
//  aizen
//
//  Thread-safe ISO8601 parsing with fractional seconds fallback
//

import Foundation

final class ISO8601DateParser: @unchecked Sendable {
    static let shared = ISO8601DateParser()

    private let lock = NSLock()
    private let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let withoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private init() {}

    func parse(_ string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return withFractional.date(from: string) ?? withoutFractional.date(from: string)
    }
}
