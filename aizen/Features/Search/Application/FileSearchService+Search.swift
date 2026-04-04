import Foundation

extension FileSearchService {
    // Fuzzy search with scoring
    func search(
        query: String,
        in results: [FileSearchIndexResult],
        worktreePath: String,
        limit: Int = 200
    ) async -> [FileSearchIndexResult] {
        guard !query.isEmpty else {
            let recent = getRecentFileResults(for: worktreePath, from: results)
            if !recent.isEmpty { return Array(recent.prefix(limit)) }
            return Array(results.prefix(limit))
        }

        let lowercaseQuery = query.lowercased()
        var scoredResults: [FileSearchIndexResult] = []
        scoredResults.reserveCapacity(min(limit * 4, 1000))

        for var result in results {
            let relativePath = result.relativePath.lowercased()
            let fileName = lastPathComponentLowercased(relativePath)

            let fileNameScore = fuzzyMatch(query: lowercaseQuery, target: fileName)
            let pathScore = fuzzyMatch(query: lowercaseQuery, target: relativePath) * 0.6

            let totalScore = max(fileNameScore, pathScore)
            if totalScore > 0 {
                result.matchScore = totalScore
                scoredResults.append(result)
            }

            if scoredResults.count >= max(limit * 6, 600) {
                scoredResults.sort { $0.matchScore > $1.matchScore }
                scoredResults = Array(scoredResults.prefix(limit))
            }
        }

        scoredResults.sort { $0.matchScore > $1.matchScore }
        return Array(scoredResults.prefix(limit))
    }

    // Track recently opened files
    func addRecentFile(_ path: String, worktreePath: String) {
        var files = recentFiles[worktreePath] ?? []
        files.removeAll { $0 == path }
        files.insert(path, at: 0)
        if files.count > maxRecentFiles {
            files.removeLast()
        }
        recentFiles[worktreePath] = files
    }

    // Get recent files as results
    func getRecentFileResults(for worktreePath: String, from allResults: [FileSearchIndexResult]) -> [FileSearchIndexResult] {
        guard let files = recentFiles[worktreePath] else { return [] }

        var results: [FileSearchIndexResult] = []
        for recentPath in files {
            if let result = allResults.first(where: { $0.path == recentPath }) {
                results.append(result)
            }
        }
        return results
    }

    func lastPathComponentLowercased(_ path: String) -> String {
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }

    // Fuzzy matching algorithm with scoring
    func fuzzyMatch(query: String, target: String) -> Double {
        guard !query.isEmpty else { return 0 }

        var score: Double = 0
        var queryIndex = query.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveMatches = 0

        if target == query {
            return 1000.0
        }

        if target.hasPrefix(query) {
            return 500.0 + Double(query.count)
        }

        var targetIndex = target.startIndex
        while targetIndex < target.endIndex {
            let targetChar = target[targetIndex]
            if queryIndex < query.endIndex && targetChar == query[queryIndex] {
                score += 10.0

                if let last = lastMatchIndex, target.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += Double(consecutiveMatches) * 5.0
                } else {
                    consecutiveMatches = 0
                }

                if targetIndex == target.startIndex {
                    score += 15.0
                } else {
                    let prev = target[target.index(before: targetIndex)]
                    if prev == "/" || prev == "." {
                        score += 15.0
                    }
                }

                lastMatchIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            }

            targetIndex = target.index(after: targetIndex)
        }

        if queryIndex == query.endIndex {
            score -= Double(target.count) * 0.1
            return score
        }

        return 0
    }
}
