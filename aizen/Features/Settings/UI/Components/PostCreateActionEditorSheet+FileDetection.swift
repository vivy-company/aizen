import Foundation

extension PostCreateActionEditorSheet {
    func scanRepository() {
        guard let repoPath = repositoryPath else { return }
        detectedFiles = scanForUntrackedFiles(at: repoPath)
    }

    func scanForUntrackedFiles(at path: String) -> [DetectedFile] {
        let fm = FileManager.default
        var result: [DetectedFile] = []

        let gitignorePatterns = parseGitignore(at: path)
        let lfsPatterns = parseLFSPatterns(at: path)

        for lfsPattern in lfsPatterns {
            if !lfsPattern.contains("*") {
                let fullPath = (path as NSString).appendingPathComponent(lfsPattern)
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                    result.append(
                        DetectedFile(
                            id: lfsPattern,
                            path: lfsPattern,
                            name: lfsPattern,
                            isDirectory: isDirectory.boolValue,
                            category: .lfs
                        )
                    )
                }
            } else {
                result.append(
                    DetectedFile(
                        id: lfsPattern,
                        path: lfsPattern,
                        name: lfsPattern,
                        isDirectory: false,
                        category: .lfs
                    )
                )
            }
        }

        let skipItems: Set<String> = [".git", ".DS_Store"]

        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return result }

        for item in contents {
            if skipItems.contains(item) { continue }

            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDirectory) else { continue }

            let isDir = isDirectory.boolValue

            if matchesAnyPattern(item, patterns: gitignorePatterns)
                || matchesAnyPattern(item + "/", patterns: gitignorePatterns) {
                result.append(
                    DetectedFile(
                        id: item,
                        path: isDir ? "\(item)/**" : item,
                        name: item,
                        isDirectory: isDir,
                        category: .gitignored
                    )
                )
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.category.order != rhs.category.order {
                return lhs.category.order < rhs.category.order
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func parseGitignore(at repoPath: String) -> [String] {
        let gitignorePath = (repoPath as NSString).appendingPathComponent(".gitignore")
        guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else { return [] }

        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func parseLFSPatterns(at repoPath: String) -> [String] {
        let gitattributesPath = (repoPath as NSString).appendingPathComponent(".gitattributes")
        guard let content = try? String(contentsOfFile: gitattributesPath, encoding: .utf8) else { return [] }

        var patterns: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("filter=lfs"),
               let pattern = trimmed.components(separatedBy: .whitespaces).first {
                patterns.append(pattern)
            }
        }
        return patterns
    }

    func matchesAnyPattern(_ name: String, patterns: [String]) -> Bool {
        for pattern in patterns where matchesGitPattern(name, pattern: pattern) {
            return true
        }
        return false
    }

    func matchesGitPattern(_ name: String, pattern: String) -> Bool {
        var p = pattern

        if p.hasPrefix("!") { return false }
        if p.hasPrefix("/") {
            p = String(p.dropFirst())
        }
        if p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        if name == p { return true }

        if p.contains("*") {
            if p.hasPrefix("*") {
                let suffix = String(p.dropFirst())
                if name.hasSuffix(suffix) { return true }
            }
            if p.hasSuffix("*") {
                let prefix = String(p.dropLast())
                if name.hasPrefix(prefix) { return true }
            }
            if p == "**" { return true }
        }

        return false
    }
}
