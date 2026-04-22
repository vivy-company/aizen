import Foundation

nonisolated final class FFFClient: @unchecked Sendable {
    private let basePath: String
    private let bridge: FFFBridge
    private let handle: UnsafeMutableRawPointer
    private let queue: DispatchQueue

    init(basePath: String) throws {
        let canonicalBasePath = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().standardized.path
        let bridge = try FFFBridgeProvider.shared()
        let databasePaths = try FFFDatabasePaths(worktreePath: canonicalBasePath)
        let queue = DispatchQueue(label: "win.aizen.project-search.\(UUID().uuidString)")
        let result = try Self.withCString(canonicalBasePath) { baseCString in
            try Self.withOptionalCString(databasePaths.frecencyURL.path) { frecencyCString in
                try Self.withOptionalCString(databasePaths.historyURL.path) { historyCString in
                    bridge.createInstance(
                        baseCString,
                        frecencyCString,
                        historyCString,
                        false,
                        true,
                        true,
                        true,
                        true
                    )
                }
            }
        }

        self.basePath = canonicalBasePath
        self.bridge = bridge
        self.queue = queue
        self.handle = try Self.unwrapHandle(from: result, using: bridge, operation: "create fff instance")
    }

    deinit {
        queue.sync {
            bridge.destroy(handle)
        }
    }

    nonisolated func searchFiles(query: String, limit: Int) throws -> ProjectFileSearchResponse {
        try queue.sync {
            let resultPointer = try Self.withCString(query) { queryCString in
                bridge.search(handle, queryCString, nil, 0, 0, UInt32(limit), 0, 0)
            }

            let payload = try Self.unwrapHandle(
                from: resultPointer,
                using: bridge,
                operation: "search project files"
            ).assumingMemoryBound(to: FffSearchResult.self)

            defer {
                bridge.freeSearchResult(payload)
            }

            let searchResult = payload.pointee
            let items = Self.buffer(from: searchResult.items, count: Int(searchResult.count))
            let scores = Self.buffer(from: searchResult.scores, count: Int(searchResult.count))

            let results = zip(items, scores).map { item, score in
                let relativePath = Self.string(from: item.relativePath) ?? ""
                let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
                return ProjectSearchFileResult(
                    path: fullPath,
                    relativePath: relativePath,
                    name: Self.string(from: item.fileName) ?? URL(fileURLWithPath: fullPath).lastPathComponent,
                    matchScore: Int(score.total),
                    openRequest: Self.searchOpenRequest(
                        for: searchResult.location,
                        path: fullPath
                    ) ?? SearchOpenRequest(path: fullPath)
                )
            }

            return ProjectFileSearchResponse(
                results: results,
                totalMatched: Int(searchResult.totalMatched),
                totalFiles: Int(searchResult.totalFiles),
                status: try scanProgressLocked()
            )
        }
    }

    nonisolated func liveGrep(
        query: String,
        mode: ProjectSearchGrepMode,
        limit: Int,
        fileOffset: Int
    ) throws -> ProjectContentSearchResponse {
        try queue.sync {
            let resultPointer = try Self.withCString(query) { queryCString in
                bridge.liveGrep(
                    handle,
                    queryCString,
                    mode.fffModeValue,
                    0,
                    0,
                    true,
                    UInt32(fileOffset),
                    UInt32(limit),
                    0,
                    2,
                    2,
                    true
                )
            }

            let payload = try Self.unwrapHandle(
                from: resultPointer,
                using: bridge,
                operation: "search project contents"
            ).assumingMemoryBound(to: FffGrepResult.self)

            defer {
                bridge.freeGrepResult(payload)
            }

            let grepResult = payload.pointee
            let matches = Self.buffer(from: grepResult.items, count: Int(grepResult.count))
            let results = matches.map { match in
                let relativePath = Self.string(from: match.relativePath) ?? ""
                let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
                let highlight = Self.firstMatchRange(from: match)
                let startColumn = Int(match.col) + 1
                let endColumn = highlight.map { Int($0.end) + 1 } ?? (startColumn + 1)

                return ProjectSearchContentResult(
                    path: fullPath,
                    relativePath: relativePath,
                    name: Self.string(from: match.fileName) ?? URL(fileURLWithPath: fullPath).lastPathComponent,
                    lineContent: Self.string(from: match.lineContent) ?? "",
                    lineNumber: Int(match.lineNumber),
                    column: startColumn,
                    contextBefore: Self.stringArray(from: match.contextBefore, count: Int(match.contextBeforeCount)),
                    contextAfter: Self.stringArray(from: match.contextAfter, count: Int(match.contextAfterCount)),
                    isDefinition: match.isDefinition,
                    openRequest: SearchOpenRequest(
                        path: fullPath,
                        line: Int(match.lineNumber),
                        column: startColumn,
                        endLine: Int(match.lineNumber),
                        endColumn: endColumn
                    )
                )
            }

            return ProjectContentSearchResponse(
                results: results,
                totalMatched: Int(grepResult.totalMatched),
                totalFiles: Int(grepResult.totalFiles),
                nextFileOffset: grepResult.nextFileOffset == 0 ? nil : Int(grepResult.nextFileOffset),
                regexFallbackError: Self.optionalString(from: grepResult.regexFallbackError),
                status: try scanProgressLocked()
            )
        }
    }

    nonisolated func scanProgress() throws -> ProjectSearchStatus {
        try queue.sync {
            try scanProgressLocked()
        }
    }

    nonisolated private func scanProgressLocked() throws -> ProjectSearchStatus {
        let resultPointer = bridge.getScanProgress(handle)
        let payload = try Self.unwrapHandle(
            from: resultPointer,
            using: bridge,
            operation: "get search scan progress"
        ).assumingMemoryBound(to: FffScanProgress.self)

        defer {
            bridge.freeScanProgress(payload)
        }

        let progress = payload.pointee
        return ProjectSearchStatus(
            scannedFilesCount: Int(progress.scannedFilesCount),
            isScanning: progress.isScanning,
            isWatcherReady: progress.isWatcherReady,
            isWarmupComplete: progress.isWarmupComplete
        )
    }

    nonisolated func trackQuery(_ query: String, selectedPath: String) throws {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        try queue.sync {
            _ = try Self.withCString(query) { queryCString in
                try Self.withCString(selectedPath) { pathCString in
                    let resultPointer = bridge.trackQuery(handle, queryCString, pathCString)
                    _ = try Self.unwrapIntValue(
                        from: resultPointer,
                        using: bridge,
                        operation: "track project-search query"
                    )
                }
            }
        }
    }

    nonisolated func refreshGitStatus() throws {
        try queue.sync {
            let resultPointer = bridge.refreshGitStatus(handle)
            _ = try Self.unwrapIntValue(
                from: resultPointer,
                using: bridge,
                operation: "refresh project-search git status"
            )
        }
    }

    private static func unwrapHandle(
        from resultPointer: UnsafeMutableRawPointer?,
        using bridge: FFFBridge,
        operation: String
    ) throws -> UnsafeMutableRawPointer {
        guard let resultPointer else {
            throw FFFBridgeError.operationFailed("fff failed to \(operation): no result returned")
        }

        defer {
            bridge.freeResult(resultPointer)
        }

        let result = resultPointer.assumingMemoryBound(to: FffResult.self).pointee
        guard result.success else {
            let message = optionalString(from: result.error) ?? "Unknown error"
            throw FFFBridgeError.operationFailed("fff failed to \(operation): \(message)")
        }

        guard let handle = result.handle else {
            throw FFFBridgeError.operationFailed("fff returned an empty handle while trying to \(operation)")
        }

        return handle
    }

    private static func unwrapIntValue(
        from resultPointer: UnsafeMutableRawPointer?,
        using bridge: FFFBridge,
        operation: String
    ) throws -> Int {
        guard let resultPointer else {
            throw FFFBridgeError.operationFailed("fff failed to \(operation): no result returned")
        }

        defer {
            bridge.freeResult(resultPointer)
        }

        let result = resultPointer.assumingMemoryBound(to: FffResult.self).pointee
        guard result.success else {
            let message = optionalString(from: result.error) ?? "Unknown error"
            throw FFFBridgeError.operationFailed("fff failed to \(operation): \(message)")
        }

        return Int(result.intValue)
    }

    private static func searchOpenRequest(for location: FffLocation, path: String?) -> SearchOpenRequest? {
        guard let path else { return nil }

        switch location.tag {
        case 1:
            return SearchOpenRequest(path: path, line: Int(location.line))
        case 2:
            return SearchOpenRequest(
                path: path,
                line: Int(location.line),
                column: Int(location.col)
            )
        case 3:
            return SearchOpenRequest(
                path: path,
                line: Int(location.line),
                column: Int(location.col),
                endLine: Int(location.endLine),
                endColumn: Int(location.endCol)
            )
        default:
            return SearchOpenRequest(path: path)
        }
    }

    private static func string(from pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(cString: pointer)
    }

    private static func optionalString(from pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let value = string(from: pointer), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func stringArray(
        from pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        count: Int
    ) -> [String] {
        guard let pointer, count > 0 else { return [] }
        let buffer = UnsafeBufferPointer(start: pointer, count: count)
        return buffer.compactMap { element in
            guard let element else { return nil }
            return String(cString: element)
        }
    }

    private static func firstMatchRange(from match: FffGrepMatch) -> FffMatchRange? {
        guard let pointer = match.matchRanges, match.matchRangesCount > 0 else {
            return nil
        }
        return pointer[0]
    }

    private static func buffer<T>(from pointer: UnsafeMutablePointer<T>?, count: Int) -> [T] {
        guard let pointer, count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private static func withCString<T>(_ value: String, _ body: (UnsafePointer<CChar>?) throws -> T) throws -> T {
        try value.withCString { pointer in
            try body(pointer)
        }
    }

    private static func withOptionalCString<T>(_ value: String?, _ body: (UnsafePointer<CChar>?) throws -> T) throws -> T {
        guard let value else {
            return try body(nil)
        }
        return try withCString(value, body)
    }
}
