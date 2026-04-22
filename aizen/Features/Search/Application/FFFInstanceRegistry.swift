import Foundation

actor FFFInstanceRegistry {
    private struct Entry {
        let client: FFFClient
        var lastAccess: Date
    }

    private var entries: [String: Entry] = [:]
    private let maxWarmInstances = 4

    func client(for worktreePath: String) throws -> FFFClient {
        let canonicalPath = URL(fileURLWithPath: worktreePath).resolvingSymlinksInPath().standardized.path

        if var existing = entries[canonicalPath] {
            existing.lastAccess = Date()
            entries[canonicalPath] = existing
            return existing.client
        }

        let client = try FFFClient(basePath: canonicalPath)
        entries[canonicalPath] = Entry(client: client, lastAccess: Date())
        evictIfNeeded(keeping: canonicalPath)
        return client
    }

    func clear(worktreePath: String) {
        let canonicalPath = URL(fileURLWithPath: worktreePath).resolvingSymlinksInPath().standardized.path
        entries.removeValue(forKey: canonicalPath)
    }

    private func evictIfNeeded(keeping activePath: String) {
        while entries.count > maxWarmInstances {
            guard let candidate = entries
                .filter({ $0.key != activePath })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
                break
            }
            entries.removeValue(forKey: candidate.key)
        }
    }
}
