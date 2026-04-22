import CryptoKit
import Foundation

nonisolated struct FFFDatabasePaths {
    let frecencyURL: URL
    let historyURL: URL

    init(worktreePath: String) throws {
        let digest = SHA256.hash(data: Data(worktreePath.utf8))
        let hash = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let root = try Self.rootDirectory()
        frecencyURL = root.appendingPathComponent("\(hash)-frecency", isDirectory: true)
        historyURL = root.appendingPathComponent("\(hash)-history", isDirectory: true)
    }

    private static func rootDirectory() throws -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "win.aizen.app"
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseDirectory
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("ProjectSearch", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
