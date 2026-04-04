//
//  FileSearchService.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation

nonisolated struct FileSearchIndexResult: Identifiable, Sendable {
    let basePath: String
    let relativePath: String
    let isDirectory: Bool
    var matchScore: Double = 0

    var path: String {
        (basePath as NSString).appendingPathComponent(relativePath)
    }

    var id: String { relativePath }
}

actor FileSearchService {
    static let shared = FileSearchService()

    var cachedResults: [String: [FileSearchIndexResult]] = [:]
    var cacheOrder: [String] = []
    let maxCachedDirectories = 4
    var recentFiles: [String: [String]] = [:]
    let maxRecentFiles = 10

    private init() {}

    // Clear cache for specific path
    func clearCache(for path: String) {
        cachedResults.removeValue(forKey: path)
        cacheOrder.removeAll { $0 == path }
        recentFiles.removeValue(forKey: path)
    }

    // Clear all caches
    func clearAllCaches() {
        cachedResults.removeAll()
        cacheOrder.removeAll()
        recentFiles.removeAll()
    }

    // MARK: - Private Helpers

    func touchCacheKey(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    func evictCacheIfNeeded() {
        while cacheOrder.count > maxCachedDirectories {
            guard let evictKey = cacheOrder.first else { break }
            cacheOrder.removeFirst()
            cachedResults.removeValue(forKey: evictKey)
            recentFiles.removeValue(forKey: evictKey)
        }
    }

}
