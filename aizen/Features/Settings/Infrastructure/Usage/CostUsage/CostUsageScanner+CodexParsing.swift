import Foundation

extension CostUsageScanner {
    struct CodexParseResult: Sendable {
        let days: [String: [String: [Int]]]
        let parsedBytes: Int64
        let lastModel: String?
        let lastTotals: CostUsageCodexTotals?
    }

    nonisolated static func parseCodexFile(
        fileURL: URL,
        range: CostUsageDayRange,
        startOffset: Int64 = 0,
        initialModel: String? = nil,
        initialTotals: CostUsageCodexTotals? = nil
    ) -> CodexParseResult {
        var currentModel = initialModel
        var previousTotals = initialTotals

        var days: [String: [String: [Int]]] = [:]

        func add(dayKey: String, model: String, input: Int, cached: Int, output: Int) {
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return }
            let normModel = CostUsagePricing.normalizeCodexModel(model)

            var dayModels = days[dayKey] ?? [:]
            var packed = dayModels[normModel] ?? [0, 0, 0]
            packed[0] = (packed[safe: 0] ?? 0) + input
            packed[1] = (packed[safe: 1] ?? 0) + cached
            packed[2] = (packed[safe: 2] ?? 0) + output
            dayModels[normModel] = packed
            days[dayKey] = dayModels
        }

        let maxLineBytes = 256 * 1024
        let prefixBytes = 32 * 1024

        let parsedBytes = (try? CostUsageJsonl.scan(
            fileURL: fileURL,
            offset: startOffset,
            maxLineBytes: maxLineBytes,
            prefixBytes: prefixBytes,
            onLine: { line in
                guard !line.bytes.isEmpty else { return }
                guard !line.wasTruncated else { return }

                guard
                    line.bytes.containsAscii(#""type":"event_msg""#)
                    || line.bytes.containsAscii(#""type":"turn_context""#)
                else { return }

                if line.bytes.containsAscii(#""type":"event_msg""#), !line.bytes.containsAscii(#""token_count""#) {
                    return
                }

                guard
                    let obj = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                    let type = obj["type"] as? String
                else { return }

                guard let tsText = obj["timestamp"] as? String else { return }
                guard let dayKey = Self.dayKeyFromTimestamp(tsText) ?? Self.dayKeyFromParsedISO(tsText) else { return }

                if type == "turn_context" {
                    if let payload = obj["payload"] as? [String: Any] {
                        if let model = payload["model"] as? String {
                            currentModel = model
                        } else if let info = payload["info"] as? [String: Any], let model = info["model"] as? String {
                            currentModel = model
                        }
                    }
                    return
                }

                guard type == "event_msg" else { return }
                guard let payload = obj["payload"] as? [String: Any] else { return }
                guard (payload["type"] as? String) == "token_count" else { return }

                let info = payload["info"] as? [String: Any]
                let modelFromInfo = info?["model"] as? String
                    ?? info?["model_name"] as? String
                    ?? payload["model"] as? String
                    ?? obj["model"] as? String
                let model = modelFromInfo ?? currentModel ?? "gpt-5"

                func toInt(_ value: Any?) -> Int {
                    if let number = value as? NSNumber {
                        return number.intValue
                    }
                    return 0
                }

                let total = info?["total_token_usage"] as? [String: Any]
                let last = info?["last_token_usage"] as? [String: Any]

                var deltaInput = 0
                var deltaCached = 0
                var deltaOutput = 0

                if let total {
                    let input = toInt(total["input_tokens"])
                    let cached = toInt(total["cached_input_tokens"] ?? total["cache_read_input_tokens"])
                    let output = toInt(total["output_tokens"])

                    let previous = previousTotals
                    deltaInput = max(0, input - (previous?.input ?? 0))
                    deltaCached = max(0, cached - (previous?.cached ?? 0))
                    deltaOutput = max(0, output - (previous?.output ?? 0))
                    previousTotals = CostUsageCodexTotals(input: input, cached: cached, output: output)
                } else if let last {
                    deltaInput = max(0, toInt(last["input_tokens"]))
                    deltaCached = max(0, toInt(last["cached_input_tokens"] ?? last["cache_read_input_tokens"]))
                    deltaOutput = max(0, toInt(last["output_tokens"]))
                } else {
                    return
                }

                if deltaInput == 0, deltaCached == 0, deltaOutput == 0 {
                    return
                }
                add(dayKey: dayKey, model: model, input: deltaInput, cached: deltaCached, output: deltaOutput)
            })
        ) ?? startOffset

        return CodexParseResult(
            days: days,
            parsedBytes: parsedBytes,
            lastModel: currentModel,
            lastTotals: previousTotals
        )
    }
}
