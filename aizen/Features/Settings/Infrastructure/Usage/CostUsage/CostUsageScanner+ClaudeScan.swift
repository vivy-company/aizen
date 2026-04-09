import Foundation

extension CostUsageScanner {
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
}
