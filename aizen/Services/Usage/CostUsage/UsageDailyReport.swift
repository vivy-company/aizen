//
//  UsageDailyReport.swift
//  aizen
//
//  Daily usage report model for local log scanning
//

import Foundation

nonisolated struct UsageDailyReport: Sendable, Equatable {
    nonisolated struct Entry: Sendable, Equatable {
        let date: String
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?
        let costUSD: Double?
        let modelsUsed: [String]?

        init(
            date: String,
            inputTokens: Int?,
            outputTokens: Int?,
            totalTokens: Int?,
            costUSD: Double?,
            modelsUsed: [String]? = nil
        ) {
            self.date = date
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.totalTokens = totalTokens
            self.costUSD = costUSD
            self.modelsUsed = modelsUsed
        }
    }

    nonisolated struct Summary: Sendable, Equatable {
        let totalInputTokens: Int?
        let totalOutputTokens: Int?
        let totalTokens: Int?
        let totalCostUSD: Double?
    }

    let data: [Entry]
    let summary: Summary?
}
