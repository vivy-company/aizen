import Foundation
import Clibgit2

/// Parses ~/.ssh/config to find the IdentityFile for a given host
nonisolated struct SSHConfigResolution: Sendable {
    let hostName: String?
    let user: String?
    let port: Int?
    let identityFiles: [String]
}

nonisolated func resolveSSHConfig(forHost host: String) -> SSHConfigResolution? {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let configPath = "\(homeDir)/.ssh/config"

    guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
        return nil
    }

    struct Entry {
        let patterns: [String]
        var hostName: String?
        var user: String?
        var port: Int?
        var identityFiles: [String]
    }

    var entries: [Entry] = []
    var currentPatterns: [String] = []
    var currentHostName: String?
    var currentUser: String?
    var currentPort: Int?
    var currentIdentityFiles: [String] = []

    func flushCurrentEntry() {
        guard !currentPatterns.isEmpty else { return }
        entries.append(Entry(
            patterns: currentPatterns,
            hostName: currentHostName,
            user: currentUser,
            port: currentPort,
            identityFiles: currentIdentityFiles
        ))
    }

    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            continue
        }

        let lower = trimmed.lowercased()

        if lower.hasPrefix("host ") {
            flushCurrentEntry()

            let remainder = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            currentPatterns = remainder.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            currentHostName = nil
            currentUser = nil
            currentPort = nil
            currentIdentityFiles = []
            continue
        }

        if lower.hasPrefix("hostname ") {
            currentHostName = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            continue
        }

        if lower.hasPrefix("user ") {
            currentUser = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            continue
        }

        if lower.hasPrefix("port ") {
            let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            currentPort = Int(value)
            continue
        }

        if lower.hasPrefix("identityfile ") {
            let value = String(trimmed.dropFirst(13)).trimmingCharacters(in: .whitespaces)
            currentIdentityFiles.append(expandPath(value))
            continue
        }
    }

    flushCurrentEntry()

    guard !entries.isEmpty else { return nil }

    // Apply matching entries in order; later matches override earlier ones.
    var resolvedHostName: String?
    var resolvedUser: String?
    var resolvedPort: Int?
    var resolvedIdentityFiles: [String] = []

    for entry in entries {
        guard entry.patterns.contains(where: { matchesHost(host, pattern: $0) }) else { continue }
        if let hn = entry.hostName { resolvedHostName = hn }
        if let u = entry.user { resolvedUser = u }
        if let p = entry.port { resolvedPort = p }
        if !entry.identityFiles.isEmpty { resolvedIdentityFiles = entry.identityFiles }
    }

    return SSHConfigResolution(
        hostName: resolvedHostName,
        user: resolvedUser,
        port: resolvedPort,
        identityFiles: resolvedIdentityFiles
    )
}

nonisolated func findSSHKeyForHost(_ host: String) -> String? {
    resolveSSHConfig(forHost: host)?.identityFiles.first
}

/// Check if host matches pattern (supports * wildcard)
nonisolated private func matchesHost(_ host: String, pattern: String) -> Bool {
    if pattern == "*" {
        return true
    }
    if pattern.contains("*") {
        let regex = pattern.replacingOccurrences(of: ".", with: "\\.").replacingOccurrences(of: "*", with: ".*")
        return host.range(of: "^\(regex)$", options: .regularExpression, range: nil, locale: nil) != nil
    }
    return host.lowercased() == pattern.lowercased()
}

/// Expand ~ in path
nonisolated private func expandPath(_ path: String) -> String {
    if path.hasPrefix("~/") {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return homeDir + String(path.dropFirst(1))
    }
    return path
}

/// Extract hostname from SSH URL (e.g., git@github.com:user/repo.git -> github.com)
nonisolated func extractHostFromURL(_ urlString: String) -> String? {
    if urlString.contains("@") && urlString.contains(":") && !urlString.hasPrefix("https://") {
        if let atIndex = urlString.firstIndex(of: "@"),
           let colonIndex = urlString.firstIndex(of: ":") {
            let start = urlString.index(after: atIndex)
            if start < colonIndex {
                return String(urlString[start..<colonIndex])
            }
        }
    }

    // SCP-like without username: host:path
    if !urlString.contains("://"), let colonIndex = urlString.firstIndex(of: ":") {
        let beforeColon = String(urlString[..<colonIndex])
        if !beforeColon.isEmpty, !beforeColon.contains("/") {
            if let atIndex = beforeColon.firstIndex(of: "@") {
                let host = String(beforeColon[beforeColon.index(after: atIndex)...])
                return host.isEmpty ? nil : host
            }
            return beforeColon
        }
    }

    if let url = URL(string: urlString) {
        return url.host
    }
    return nil
}
