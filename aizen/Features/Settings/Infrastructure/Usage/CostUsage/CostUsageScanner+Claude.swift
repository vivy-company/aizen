import Foundation

extension CostUsageScanner {
    struct ClaudeParseResult: Sendable {
        let days: [String: [String: [Int]]]
        let parsedBytes: Int64
    }

    struct ClaudeTokens: Sendable {
        let input: Int
        let cacheRead: Int
        let cacheCreate: Int
        let output: Int
    }

    nonisolated static func parseClaudeFile(
        fileURL: URL,
        range: CostUsageDayRange,
        startOffset: Int64 = 0
    ) -> ClaudeParseResult {
        var days: [String: [String: [Int]]] = [:]

        func add(dayKey: String, model: String, tokens: ClaudeTokens) {
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return }
            let normModel = CostUsagePricing.normalizeClaudeModel(model)
            var dayModels = days[dayKey] ?? [:]
            var packed = dayModels[normModel] ?? [0, 0, 0, 0]
            packed[0] = (packed[safe: 0] ?? 0) + tokens.input
            packed[1] = (packed[safe: 1] ?? 0) + tokens.cacheRead
            packed[2] = (packed[safe: 2] ?? 0) + tokens.cacheCreate
            packed[3] = (packed[safe: 3] ?? 0) + tokens.output
            dayModels[normModel] = packed
            days[dayKey] = dayModels
        }

        let maxLineBytes = 256 * 1024
        let prefixBytes = 64 * 1024

        let parsedBytes = (try? CostUsageJsonl.scan(
            fileURL: fileURL,
            offset: startOffset,
            maxLineBytes: maxLineBytes,
            prefixBytes: prefixBytes,
            onLine: { line in
                guard !line.bytes.isEmpty else { return }
                guard !line.wasTruncated else { return }
                guard line.bytes.containsAscii(#""type":"assistant""#) else { return }
                guard line.bytes.containsAscii(#""usage""#) else { return }

                guard
                    let obj = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                    let type = obj["type"] as? String,
                    type == "assistant"
                else { return }

                guard let tsText = obj["timestamp"] as? String else { return }
                guard let dayKey = Self.dayKeyFromTimestamp(tsText) ?? Self.dayKeyFromParsedISO(tsText) else { return }

                guard let message = obj["message"] as? [String: Any] else { return }
                guard let model = message["model"] as? String else { return }
                guard let usage = message["usage"] as? [String: Any] else { return }

                func toInt(_ v: Any?) -> Int {
                    if let n = v as? NSNumber { return n.intValue }
                    return 0
                }

                let input = max(0, toInt(usage["input_tokens"]))
                let cacheCreate = max(0, toInt(usage["cache_creation_input_tokens"]))
                let cacheRead = max(0, toInt(usage["cache_read_input_tokens"]))
                let output = max(0, toInt(usage["output_tokens"]))
                if input == 0, cacheCreate == 0, cacheRead == 0, output == 0 { return }

                let tokens = ClaudeTokens(input: input, cacheRead: cacheRead, cacheCreate: cacheCreate, output: output)
                add(dayKey: dayKey, model: model, tokens: tokens)
            })) ?? startOffset

        return ClaudeParseResult(days: days, parsedBytes: parsedBytes)
    }

    nonisolated static func buildClaudeReportFromCache(
        cache: CostUsageCache,
        range: CostUsageDayRange
    ) -> UsageDailyReport {
        var entries: [UsageDailyReport.Entry] = []
        var totalInput = 0
        var totalOutput = 0
        var totalTokens = 0
        var totalCost: Double = 0
        var hasCost = false

        let sortedDays = cache.days.keys.sorted()
        for dayKey in sortedDays {
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.sinceKey, until: range.untilKey) else { continue }
            let dayModels = cache.days[dayKey] ?? [:]
            var dayInput = 0
            var dayOutput = 0
            var dayTotal = 0
            var dayCost: Double = 0
            var modelsUsed: [String] = []

            for (model, packed) in dayModels {
                let input = packed[safe: 0] ?? 0
                let cacheRead = packed[safe: 1] ?? 0
                let cacheCreate = packed[safe: 2] ?? 0
                let output = packed[safe: 3] ?? 0
                let modelCost = CostUsagePricing.claudeCostUSD(
                    model: model,
                    inputTokens: input,
                    cacheReadInputTokens: cacheRead,
                    cacheCreationInputTokens: cacheCreate,
                    outputTokens: output)
                if let modelCost {
                    dayCost += modelCost
                    hasCost = true
                }
                dayInput += input
                dayOutput += output
                dayTotal += max(0, input + output)
                modelsUsed.append(model)
            }

            totalInput += dayInput
            totalOutput += dayOutput
            totalTokens += dayTotal
            if hasCost { totalCost += dayCost }

            let entry = UsageDailyReport.Entry(
                date: dayKey,
                inputTokens: dayInput,
                outputTokens: dayOutput,
                totalTokens: dayTotal,
                costUSD: hasCost ? dayCost : nil,
                modelsUsed: modelsUsed.isEmpty ? nil : modelsUsed.sorted())
            entries.append(entry)
        }

        let summary = UsageDailyReport.Summary(
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalTokens: totalTokens,
            totalCostUSD: hasCost ? totalCost : nil)
        return UsageDailyReport(data: entries, summary: summary)
    }
}
