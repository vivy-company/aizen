import Foundation

/// Persists the last *reported* Host startup failure without writing user content or logs.
public enum HostStartupStatusStore {
    private static let filename = "host-startup-status.json"

    public static func clearFailure(storageURL: URL, fileManager: FileManager = .default) throws {
        let url = statusURL(for: storageURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Record(lastError: nil, consecutiveFailureCount: 0)).write(to: url, options: .atomic)
    }

    public static func recordFailure(
        _ error: Error,
        storageURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let url = statusURL(for: storageURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let previousCount = record(storageURL: storageURL, fileManager: fileManager)?.consecutiveFailureCount ?? 0
        try JSONEncoder().encode(Record(lastError: error.localizedDescription, consecutiveFailureCount: previousCount + 1)).write(to: url, options: .atomic)
    }

    public static func lastError(storageURL: URL, fileManager: FileManager = .default) -> String? {
        record(storageURL: storageURL, fileManager: fileManager)?.lastError
    }

    public static func consecutiveFailureCount(storageURL: URL, fileManager: FileManager = .default) -> Int {
        record(storageURL: storageURL, fileManager: fileManager)?.consecutiveFailureCount ?? 0
    }

    private static func statusURL(for storageURL: URL) -> URL {
        storageURL.deletingLastPathComponent().appendingPathComponent(filename)
    }

    private static func record(storageURL: URL, fileManager: FileManager) -> Record? {
        guard let data = try? Data(contentsOf: statusURL(for: storageURL)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private struct Record: Codable {
        let lastError: String?
        let consecutiveFailureCount: Int
    }
}
