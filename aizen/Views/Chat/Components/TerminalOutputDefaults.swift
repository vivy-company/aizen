//
//  TerminalOutputDefaults.swift
//  aizen
//
//  Shared defaults for terminal output previews
//

enum TerminalOutputDefaults {
    static let maxDisplayChars = 20_000
    static let gracePeriodIterations = 3
    static let pollIntervalNanoseconds: UInt64 = 500_000_000
    static let maxPollIterationsDetail = 60 // 30s @ 0.5s
    static let maxPollIterationsInline = 120 // 60s @ 0.5s
}
