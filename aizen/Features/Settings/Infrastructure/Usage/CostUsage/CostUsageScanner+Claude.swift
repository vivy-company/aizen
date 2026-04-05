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

    struct ClaudeScanState: Sendable {
        var cache: CostUsageCache
        var processedFiles: Set<String> = []
    }

    nonisolated static func defaultClaudeProjectsRoots(options: Options) -> [URL] {
        if let override = options.claudeProjectsRoots { return override }

        var roots: [URL] = []

        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !env.isEmpty {
            for part in env.split(separator: ",") {
                let raw = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                let url = URL(fileURLWithPath: raw)
                if url.lastPathComponent == "projects" {
                    roots.append(url)
                } else {
                    roots.append(url.appendingPathComponent("projects", isDirectory: true))
                }
            }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            roots.append(home.appendingPathComponent(".config/claude/projects", isDirectory: true))
            roots.append(home.appendingPathComponent(".claude/projects", isDirectory: true))
        }

        return roots
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

    nonisolated static func processClaudeFile(
        url: URL,
        range: CostUsageDayRange,
        state: inout ClaudeScanState
    ) {
        let path = url.path
        guard state.processedFiles.contains(path) == false else { return }
        state.processedFiles.insert(path)

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeMs = Int64(mtime * 1000)

        if let existing = state.cache.files[path],
           existing.mtimeUnixMs == mtimeMs,
           existing.size == size {
            return
        }

        let existing = state.cache.files[path]
        let startOffset = existing?.parsedBytes ?? 0
        let parsed = Self.parseClaudeFile(fileURL: url, range: range, startOffset: startOffset)
        let usage = CostUsageFileUsage(
            mtimeUnixMs: mtimeMs,
            size: size,
            days: parsed.days,
            parsedBytes: parsed.parsedBytes,
            lastModel: nil,
            lastTotals: nil)
        state.cache.files[path] = usage
        state.cache.days = Self.applyFileDays(cache: state.cache.days, fileDays: usage.days, sign: 1)
    }

    nonisolated static func scanClaudeRoot(
        root: URL,
        range: CostUsageDayRange,
        state: inout ClaudeScanState
    ) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return }

        for item in items {
            let path = item.path
            if state.processedFiles.contains(path) { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
            if !isDir { continue }

            if let subItems = try? fm.subpathsOfDirectory(atPath: path) {
                for subPath in subItems where subPath.hasSuffix(".jsonl") {
                    let url = URL(fileURLWithPath: path).appendingPathComponent(subPath)
                    Self.processClaudeFile(url: url, range: range, state: &state)
                }
            }
        }
    }

    nonisolated static func loadClaudeDaily(
        range: CostUsageDayRange,
        now: Date,
        options: Options
    ) -> UsageDailyReport {
        let cache = CostUsageCacheIO.load(provider: .claude, cacheRoot: options.cacheRoot)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let minInterval = Int64(max(1, options.refreshMinIntervalSeconds) * 1000)
        if nowMs - cache.lastScanUnixMs < minInterval {
            return self.buildClaudeReportFromCache(cache: cache, range: range)
        }

        let roots = self.defaultClaudeProjectsRoots(options: options)
        var mutable = cache
        var scanState = ClaudeScanState(cache: mutable)

        for root in roots {
            Self.scanClaudeRoot(root: root, range: range, state: &scanState)
        }
        mutable = scanState.cache
        mutable.lastScanUnixMs = nowMs
        CostUsageCacheIO.save(provider: .claude, cache: mutable, cacheRoot: options.cacheRoot)
        return self.buildClaudeReportFromCache(cache: mutable, range: range)
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
