//
//  DurationFormatter.swift
//  aizen
//
//  Shared duration formatting helpers
//

import Foundation

enum DurationFormatter {
    static func short(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}
