import Foundation

enum CommandPaletteQueryParser {
    static func parse(
        _ query: String,
        fallbackScope: CommandPaletteScope
    ) -> (scope: CommandPaletteScope, query: String, isExplicit: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (fallbackScope, "", false) }

        let lower = trimmed.lowercased()
        let commandPairs: [(String, CommandPaletteScope)] = [
            ("all:", .all),
            ("all ", .all),
            ("a:", .all),
            ("a ", .all),
            ("workspace:", .workspace),
            ("workspace ", .workspace),
            ("w:", .workspace),
            ("w ", .workspace),
            ("ws:", .workspace),
            ("ws ", .workspace),
            ("tabs:", .tabs),
            ("tabs ", .tabs),
            ("tab:", .tabs),
            ("tab ", .tabs),
            ("t:", .tabs),
            ("t ", .tabs),
            ("project:", .currentProject),
            ("project ", .currentProject),
            ("repo:", .currentProject),
            ("repo ", .currentProject),
            ("current:", .currentProject),
            ("current ", .currentProject),
            ("local:", .currentProject),
            ("local ", .currentProject),
            ("cp:", .currentProject),
            ("cp ", .currentProject),
            ("env:", .all),
            ("env ", .all),
            ("environment:", .all),
            ("environment ", .all),
            ("e:", .all),
            ("e ", .all)
        ]

        for (prefix, parsedScope) in commandPairs where lower.hasPrefix(prefix) {
            let stripped = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (parsedScope, stripped, true)
        }

        return (fallbackScope, trimmed, false)
    }
}

enum CommandPaletteRecency {
    static func isRecent(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= 14 * 24 * 60 * 60
    }

    static func boost(for date: Date?) -> Double {
        guard let date else { return 0 }
        let age = Date().timeIntervalSince(date)
        if age <= 60 * 10 {
            return 80
        }
        if age <= 60 * 60 {
            return 60
        }
        if age <= 60 * 60 * 24 {
            return 36
        }
        if age <= 60 * 60 * 24 * 7 {
            return 22
        }
        if age <= 60 * 60 * 24 * 30 {
            return 10
        }
        return 0
    }
}

enum CommandPaletteScorer {
    static func matchScore(query: String, fields: [String]) -> Double {
        guard !query.isEmpty else { return 0 }

        let loweredFields = fields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !loweredFields.isEmpty else { return 0 }

        var best: Double = 0
        for field in loweredFields {
            if field == query {
                best = max(best, 1200)
            } else if field.hasPrefix(query) {
                best = max(best, 720 + Double(query.count))
            } else if field.localizedCaseInsensitiveContains(query) {
                best = max(best, 420 + Double(query.count) - Double(field.count) * 0.1)
            }

            let fuzzy = fuzzyMatch(query: query, target: field)
            best = max(best, fuzzy)
        }

        if best > 0 {
            return best
        }

        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count > 1 else {
            return 0
        }

        let tokenMatch = tokens.allSatisfy { token in
            loweredFields.contains { $0.localizedCaseInsensitiveContains(token) }
        }
        return tokenMatch ? 260 + Double(tokens.count) * 10 : 0
    }

    private static func fuzzyMatch(query: String, target: String) -> Double {
        guard !query.isEmpty else { return 0 }

        var score: Double = 0
        var queryIndex = query.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveMatches = 0

        if target == query {
            return 1000
        }

        if target.hasPrefix(query) {
            return 500 + Double(query.count)
        }

        var targetIndex = target.startIndex
        while targetIndex < target.endIndex {
            let targetChar = target[targetIndex]
            if queryIndex < query.endIndex && targetChar == query[queryIndex] {
                score += 10

                if let last = lastMatchIndex, target.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += Double(consecutiveMatches) * 5
                } else {
                    consecutiveMatches = 0
                }

                if targetIndex == target.startIndex {
                    score += 15
                } else {
                    let prev = target[target.index(before: targetIndex)]
                    if prev == "/" || prev == "." || prev == " " || prev == "-" {
                        score += 15
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
