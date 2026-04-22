import Darwin
import Foundation

enum FFFBridgeError: LocalizedError {
    case libraryNotFound([String])
    case openFailed(String)
    case missingSymbol(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .libraryNotFound(let candidates):
            return "libfff_c.dylib not found. Tried: \(candidates.joined(separator: ", "))"
        case .openFailed(let message):
            return "Failed to load libfff_c.dylib: \(message)"
        case .missingSymbol(let symbol):
            return "Missing libfff_c symbol: \(symbol)"
        case .operationFailed(let message):
            return message
        }
    }
}

nonisolated struct FffResult {
    var success: Bool
    var error: UnsafeMutablePointer<CChar>?
    var handle: UnsafeMutableRawPointer?
    var intValue: Int64
}

nonisolated struct FffFileItem {
    var relativePath: UnsafeMutablePointer<CChar>?
    var fileName: UnsafeMutablePointer<CChar>?
    var gitStatus: UnsafeMutablePointer<CChar>?
    var size: UInt64
    var modified: UInt64
    var accessFrecencyScore: Int64
    var modificationFrecencyScore: Int64
    var totalFrecencyScore: Int64
    var isBinary: Bool
}

nonisolated struct FffScore {
    var total: Int32
    var baseScore: Int32
    var filenameBonus: Int32
    var specialFilenameBonus: Int32
    var frecencyBoost: Int32
    var distancePenalty: Int32
    var currentFilePenalty: Int32
    var comboMatchBoost: Int32
    var pathAlignmentBonus: Int32
    var exactMatch: Bool
    var matchType: UnsafeMutablePointer<CChar>?
}

nonisolated struct FffLocation {
    var tag: UInt8
    var line: Int32
    var col: Int32
    var endLine: Int32
    var endCol: Int32
}

nonisolated struct FffSearchResult {
    var items: UnsafeMutablePointer<FffFileItem>?
    var scores: UnsafeMutablePointer<FffScore>?
    var count: UInt32
    var totalMatched: UInt32
    var totalFiles: UInt32
    var location: FffLocation
}

nonisolated struct FffMatchRange {
    var start: UInt32
    var end: UInt32
}

nonisolated struct FffGrepMatch {
    var relativePath: UnsafeMutablePointer<CChar>?
    var fileName: UnsafeMutablePointer<CChar>?
    var gitStatus: UnsafeMutablePointer<CChar>?
    var lineContent: UnsafeMutablePointer<CChar>?
    var matchRanges: UnsafeMutablePointer<FffMatchRange>?
    var contextBefore: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var contextAfter: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var size: UInt64
    var modified: UInt64
    var totalFrecencyScore: Int64
    var accessFrecencyScore: Int64
    var modificationFrecencyScore: Int64
    var lineNumber: UInt64
    var byteOffset: UInt64
    var col: UInt32
    var matchRangesCount: UInt32
    var contextBeforeCount: UInt32
    var contextAfterCount: UInt32
    var fuzzyScore: UInt16
    var hasFuzzyScore: Bool
    var isBinary: Bool
    var isDefinition: Bool
}

nonisolated struct FffGrepResult {
    var items: UnsafeMutablePointer<FffGrepMatch>?
    var count: UInt32
    var totalMatched: UInt32
    var totalFilesSearched: UInt32
    var totalFiles: UInt32
    var filteredFileCount: UInt32
    var nextFileOffset: UInt32
    var regexFallbackError: UnsafeMutablePointer<CChar>?
}

nonisolated struct FffScanProgress {
    var scannedFilesCount: UInt64
    var isScanning: Bool
    var isWatcherReady: Bool
    var isWarmupComplete: Bool
}

typealias FFFCreateInstanceFn = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    Bool,
    Bool,
    Bool,
    Bool,
    Bool
) -> UnsafeMutableRawPointer?
typealias FFFDestroyFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias FFFSearchFn = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UInt32,
    UInt32,
    UInt32,
    Int32,
    UInt32
) -> UnsafeMutableRawPointer?
typealias FFFLiveGrepFn = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UInt8,
    UInt64,
    UInt32,
    Bool,
    UInt32,
    UInt32,
    UInt64,
    UInt32,
    UInt32,
    Bool
) -> UnsafeMutableRawPointer?
typealias FFFGetScanProgressFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
typealias FFFTrackQueryFn = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer?
typealias FFFRefreshGitStatusFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
typealias FFFFreeResultFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias FFFFreeSearchResultFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias FFFFreeGrepResultFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias FFFFreeScanProgressFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

nonisolated enum FFFBridgeProvider {
    static let sharedResult: Result<FFFBridge, Error> = Result {
        try FFFBridge()
    }

    static func shared() throws -> FFFBridge {
        try sharedResult.get()
    }
}

nonisolated final class FFFBridge {
    let handle: UnsafeMutableRawPointer
    let createInstance: FFFCreateInstanceFn
    let destroy: FFFDestroyFn
    let search: FFFSearchFn
    let liveGrep: FFFLiveGrepFn
    let getScanProgress: FFFGetScanProgressFn
    let trackQuery: FFFTrackQueryFn
    let refreshGitStatus: FFFRefreshGitStatusFn
    let freeResult: FFFFreeResultFn
    let freeSearchResult: FFFFreeSearchResultFn
    let freeGrepResult: FFFFreeGrepResultFn
    let freeScanProgress: FFFFreeScanProgressFn

    init() throws {
        let candidates = Self.candidatePaths()
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw FFFBridgeError.libraryNotFound(candidates)
        }

        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "Unknown dlopen error"
            throw FFFBridgeError.openFailed(message)
        }

        self.handle = handle
        self.createInstance = try Self.loadSymbol("fff_create_instance", from: handle)
        self.destroy = try Self.loadSymbol("fff_destroy", from: handle)
        self.search = try Self.loadSymbol("fff_search", from: handle)
        self.liveGrep = try Self.loadSymbol("fff_live_grep", from: handle)
        self.getScanProgress = try Self.loadSymbol("fff_get_scan_progress", from: handle)
        self.trackQuery = try Self.loadSymbol("fff_track_query", from: handle)
        self.refreshGitStatus = try Self.loadSymbol("fff_refresh_git_status", from: handle)
        self.freeResult = try Self.loadSymbol("fff_free_result", from: handle)
        self.freeSearchResult = try Self.loadSymbol("fff_free_search_result", from: handle)
        self.freeGrepResult = try Self.loadSymbol("fff_free_grep_result", from: handle)
        self.freeScanProgress = try Self.loadSymbol("fff_free_scan_progress", from: handle)
    }

    deinit {
        dlclose(handle)
    }

    private static func candidatePaths() -> [String] {
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["AIZEN_FFF_DYLIB_PATH"], !override.isEmpty {
            candidates.append(override)
        }

        if let frameworksURL = Bundle.main.privateFrameworksURL {
            candidates.append(frameworksURL.appendingPathComponent("libfff_c.dylib").path)
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libfff_c.dylib").path)
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/fff-c/lib/libfff_c.dylib").path)

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw FFFBridgeError.missingSymbol(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}
