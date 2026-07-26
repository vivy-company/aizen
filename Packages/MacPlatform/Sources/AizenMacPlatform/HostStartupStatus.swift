import Foundation

/// Persists the last *reported* Host startup failure without writing user content or logs.
public enum HostStartupStatusStore {
    private static let filename = "host-startup-status.json"

    public static func clearFailure(storageURL: URL, fileManager: FileManager = .default) throws {
        let url = statusURL(for: storageURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Record(lastError: nil)).write(to: url, options: .atomic)
    }

    public static func recordFailure(
        _ error: Error,
        storageURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let url = statusURL(for: storageURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Record(lastError: error.localizedDescription)).write(to: url, options: .atomic)
    }

    public static func lastError(storageURL: URL, fileManager: FileManager = .default) -> String? {
        guard let data = try? Data(contentsOf: statusURL(for: storageURL)),
              let record = try? JSONDecoder().decode(Record.self, from: data) else {
            return nil
        }
        return record.lastError
    }

    private static func statusURL(for storageURL: URL) -> URL {
        storageURL.deletingLastPathComponent().appendingPathComponent(filename)
    }

    private struct Record: Codable {
        let lastError: String?
    }
}
