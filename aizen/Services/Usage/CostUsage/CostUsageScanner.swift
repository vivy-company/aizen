//
//  CostUsageScanner.swift
//  aizen
//
//  Local usage log scanner for codex/claude
//

import Foundation

enum CostUsageScanner {
    struct Options: Sendable {
        var codexSessionsRoot: URL?
        var claudeProjectsRoots: [URL]?
        var cacheRoot: URL?
        var refreshMinIntervalSeconds: TimeInterval = 60

        init(
            codexSessionsRoot: URL? = nil,
            claudeProjectsRoots: [URL]? = nil,
            cacheRoot: URL? = nil
        ) {
            self.codexSessionsRoot = codexSessionsRoot
            self.claudeProjectsRoots = claudeProjectsRoots
            self.cacheRoot = cacheRoot
        }
    }

    struct CodexParseResult: Sendable {
        let days: [String: [String: [Int]]]
        let parsedBytes: Int64
        let lastModel: String?
        let lastTotals: CostUsageCodexTotals?
    }

    struct ClaudeParseResult: Sendable {
        let days: [String: [String: [Int]]]
        let parsedBytes: Int64
    }

    static func loadDailyReport(
        provider: UsageProvider,
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options()
    ) -> UsageDailyReport {
        let range = CostUsageDayRange(since: since, until: until)

        switch provider {
        case .codex:
            return self.loadCodexDaily(range: range, now: now, options: options)
        case .claude:
            return self.loadClaudeDaily(range: range, now: now, options: options)
        default:
            return UsageDailyReport(data: [], summary: nil)
        }
    }

    // MARK: - Day keys

    struct CostUsageDayRange: Sendable {
        let sinceKey: String
        let untilKey: String
        let scanSinceKey: String
        let scanUntilKey: String

        init(since: Date, until: Date) {
            self.sinceKey = Self.dayKey(from: since)
            self.untilKey = Self.dayKey(from: until)
            self.scanSinceKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: -1, to: since) ?? since)
            self.scanUntilKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: 1, to: until) ?? until)
        }

        static func dayKey(from date: Date) -> String {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            let y = comps.year ?? 1970
            let m = comps.month ?? 1
            let d = comps.day ?? 1
            return String(format: "%04d-%02d-%02d", y, m, d)
        }

        static func isInRange(dayKey: String, since: String, until: String) -> Bool {
            if dayKey < since { return false }
            if dayKey > until { return false }
            return true
        }
    }

    // MARK: - Codex

    private static func defaultCodexSessionsRoot(options: Options) -> URL {
        if let override = options.codexSessionsRoot { return override }
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: env).appendingPathComponent("sessions", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func listCodexSessionFiles(root: URL, scanSinceKey: String, scanUntilKey: String) -> [URL] {
        var out: [URL] = []
        var date = Self.parseDayKey(scanSinceKey) ?? Date()
        let untilDate = Self.parseDayKey(scanUntilKey) ?? date

        while date <= untilDate {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let y = String(format: "%04d", comps.year ?? 1970)
            let m = String(format: "%02d", comps.month ?? 1)
            let d = String(format: "%02d", comps.day ?? 1)

            let dayDir = root.appendingPathComponent(y, isDirectory: true)
                .appendingPathComponent(m, isDirectory: true)
                .appendingPathComponent(d, isDirectory: true)

            if let items = try? FileManager.default.contentsOfDirectory(
                at: dayDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]) {
                for item in items where item.pathExtension.lowercased() == "jsonl" {
                    out.append(item)
                }
            }

            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? untilDate.addingTimeInterval(1)
        }

        return out
    }

    static func parseCodexFile(
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

                func toInt(_ v: Any?) -> Int {
                    if let n = v as? NSNumber { return n.intValue }
                    return 0
                }

                let total = (info?["total_token_usage"] as? [String: Any])
                let last = (info?["last_token_usage"] as? [String: Any])

                var deltaInput = 0
                var deltaCached = 0
                var deltaOutput = 0

                if let total {
                    let input = toInt(total["input_tokens"])
                    let cached = toInt(total["cached_input_tokens"] ?? total["cache_read_input_tokens"])
                    let output = toInt(total["output_tokens"])

                    let prev = previousTotals
                    deltaInput = max(0, input - (prev?.input ?? 0))
                    deltaCached = max(0, cached - (prev?.cached ?? 0))
                    deltaOutput = max(0, output - (prev?.output ?? 0))
                    previousTotals = CostUsageCodexTotals(input: input, cached: cached, output: output)
                } else if let last {
                    deltaInput = max(0, toInt(last["input_tokens"]))
                    deltaCached = max(0, toInt(last["cached_input_tokens"] ?? last["cache_read_input_tokens"]))
                    deltaOutput = max(0, toInt(last["output_tokens"]))
                } else {
                    return
                }

                if deltaInput == 0, deltaCached == 0, deltaOutput == 0 { return }
                add(dayKey: dayKey, model: model, input: deltaInput, cached: deltaCached, output: deltaOutput)
            })) ?? startOffset

        return CodexParseResult(
            days: days,
            parsedBytes: parsedBytes,
            lastModel: currentModel,
            lastTotals: previousTotals
        )
    }

    private static func loadCodexDaily(
        range: CostUsageDayRange,
        now: Date,
        options: Options
    ) -> UsageDailyReport {
        let cache = CostUsageCacheIO.load(provider: .codex, cacheRoot: options.cacheRoot)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let minInterval = Int64(max(1, options.refreshMinIntervalSeconds) * 1000)
        if nowMs - cache.lastScanUnixMs < minInterval {
            return self.buildCodexReportFromCache(cache: cache, range: range)
        }

        let root = self.defaultCodexSessionsRoot(options: options)
        let files = self.listCodexSessionFiles(
            root: root,
            scanSinceKey: range.scanSinceKey,
            scanUntilKey: range.scanUntilKey)

        var mutable = cache
        for file in files {
            let path = file.path
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtimeMs = Int64(mtime * 1000)

            if let existing = mutable.files[path],
               existing.mtimeUnixMs == mtimeMs,
               existing.size == size {
                continue
            }

            let existing = mutable.files[path]
            let startOffset = existing?.parsedBytes ?? 0
            let parsed = Self.parseCodexFile(
                fileURL: file,
                range: range,
                startOffset: startOffset,
                initialModel: existing?.lastModel,
                initialTotals: existing?.lastTotals)

            let usage = CostUsageFileUsage(
                mtimeUnixMs: mtimeMs,
                size: size,
                days: parsed.days,
                parsedBytes: parsed.parsedBytes,
                lastModel: parsed.lastModel,
                lastTotals: parsed.lastTotals)
            mutable.files[path] = usage

            let fileDays = usage.days
            mutable.days = Self.applyFileDays(cache: mutable.days, fileDays: fileDays, sign: 1)
        }

        mutable.lastScanUnixMs = nowMs
        CostUsageCacheIO.save(provider: .codex, cache: mutable, cacheRoot: options.cacheRoot)
        return self.buildCodexReportFromCache(cache: mutable, range: range)
    }

    private static func buildCodexReportFromCache(
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
                let cached = packed[safe: 1] ?? 0
                let output = packed[safe: 2] ?? 0
                let modelCost = CostUsagePricing.codexCostUSD(
                    model: model,
                    inputTokens: input,
                    cachedInputTokens: cached,
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

    // MARK: - Claude

    private static func defaultClaudeProjectsRoots(options: Options) -> [URL] {
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

    static func parseClaudeFile(
        fileURL: URL,
        range: CostUsageDayRange,
        startOffset: Int64 = 0
    ) -> ClaudeParseResult {
        var days: [String: [String: [Int]]] = [:]

        struct ClaudeTokens: Sendable {
            let input: Int
            let cacheRead: Int
            let cacheCreate: Int
            let output: Int
        }

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

    private final class ClaudeScanState {
        var cache: CostUsageCache
        var processedFiles: Set<String> = []

        init(cache: CostUsageCache) {
            self.cache = cache
        }
    }

    private static func processClaudeFile(
        url: URL,
        range: CostUsageDayRange,
        state: ClaudeScanState
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

    private static func scanClaudeRoot(
        root: URL,
        range: CostUsageDayRange,
        state: ClaudeScanState
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

            // Scan all jsonl files under this project directory
            if let subItems = try? fm.subpathsOfDirectory(atPath: path) {
                for subPath in subItems where subPath.hasSuffix(".jsonl") {
                    let url = URL(fileURLWithPath: path).appendingPathComponent(subPath)
                    Self.processClaudeFile(url: url, range: range, state: state)
                }
            }
        }
    }

    private static func loadClaudeDaily(
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
        let scanState = ClaudeScanState(cache: mutable)

        for root in roots {
            Self.scanClaudeRoot(root: root, range: range, state: scanState)
        }

        mutable = scanState.cache
        mutable.lastScanUnixMs = nowMs
        CostUsageCacheIO.save(provider: .claude, cache: mutable, cacheRoot: options.cacheRoot)
        return self.buildClaudeReportFromCache(cache: mutable, range: range)
    }

    private static func buildClaudeReportFromCache(
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

    // MARK: - Cache helpers

    private static func applyFileDays(
        cache: [String: [String: [Int]]],
        fileDays: [String: [String: [Int]]],
        sign: Int
    ) -> [String: [String: [Int]]] {
        var out = cache
        for (dayKey, models) in fileDays {
            var outModels = out[dayKey] ?? [:]
            for (model, packed) in models {
                let existing = outModels[model] ?? []
                outModels[model] = Self.mergePacked(existing, packed, sign: sign)
            }
            out[dayKey] = outModels
        }
        return out
    }

    private static func mergePacked(_ a: [Int], _ b: [Int], sign: Int) -> [Int] {
        let count = max(a.count, b.count)
        var out = Array(repeating: 0, count: count)
        for idx in 0..<count {
            let next = (a[safe: idx] ?? 0) + sign * (b[safe: idx] ?? 0)
            out[idx] = max(0, next)
        }
        return out
    }

    // MARK: - Date parsing

    private static func parseDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return nil }
        guard
            let y = Int(parts[0]),
            let m = Int(parts[1]),
            let d = Int(parts[2])
        else { return nil }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        return comps.date
    }
}

extension Data {
    fileprivate func containsAscii(_ needle: String) -> Bool {
        guard let n = needle.data(using: .utf8) else { return false }
        return self.range(of: n) != nil
    }
}

extension [Int] {
    subscript(safe index: Int) -> Int? {
        if index < 0 { return nil }
        if index >= self.count { return nil }
        return self[index]
    }
}

extension [UInt8] {
    subscript(safe index: Int) -> UInt8? {
        if index < 0 { return nil }
        if index >= self.count { return nil }
        return self[index]
    }
}
