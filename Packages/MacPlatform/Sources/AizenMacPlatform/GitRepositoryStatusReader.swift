import AizenHost
import CryptoKit
import Foundation

/// macOS Git adapter for the read-only repository status capability.
///
/// Host resolves the repository URL from a Resource before this actor is called; this type never
/// receives a client-provided command or path fragment.
public actor GitRepositoryStatusReader: RepositoryStatusReading, RepositoryDiffReading {
    private static let maximumStatusBytes = 1_048_576
    private static let maximumIndexBytes = 67_108_864

    public init() {}

    public func status(at repositoryURL: URL, maximumEntries: Int) async throws -> RepositoryStatusSnapshot {
        guard maximumEntries > 0, FileManager.default.fileExists(atPath: repositoryURL.appendingPathComponent(".git").path) else {
            throw Error.notRepository
        }

        let statusOutput = try runGitData(
            ["-C", repositoryURL.path, "status", "--porcelain=v2", "-z", "--untracked-files=normal"],
            maximumOutputBytes: Self.maximumStatusBytes
        )
        let entries = try parseStatus(statusOutput, maximumEntries: maximumEntries)
        let repositoryRevision = try currentRepositoryRevision(at: repositoryURL)
        let indexRevision = try currentIndexRevision(at: repositoryURL)
        return .init(
            repositoryRevision: repositoryRevision,
            indexRevision: indexRevision,
            entries: entries.entries,
            truncated: entries.truncated
        )
    }

    public func diff(at repositoryURL: URL, relativePath: String, maximumBytes: Int) async throws -> RepositoryDiffSnapshot {
        guard maximumBytes > 0, FileManager.default.fileExists(atPath: repositoryURL.appendingPathComponent(".git").path) else { throw Error.notRepository }
        let pathArguments = relativePath.isEmpty ? [] : ["--", relativePath]
        let diffArguments: [String]
        if (try? runGit(["-C", repositoryURL.path, "rev-parse", "--verify", "HEAD"], maximumOutputBytes: 512)) != nil {
            diffArguments = ["-C", repositoryURL.path, "diff", "--no-ext-diff", "--no-color", "--no-textconv", "--binary", "HEAD"] + pathArguments
        } else {
            diffArguments = ["-C", repositoryURL.path, "diff", "--no-ext-diff", "--no-color", "--no-textconv", "--binary", "--cached"] + pathArguments
        }
        let output = try runGitData(diffArguments, maximumOutputBytes: maximumBytes)
        return .init(repositoryRevision: try currentRepositoryRevision(at: repositoryURL), indexRevision: try currentIndexRevision(at: repositoryURL), unifiedDiff: output, truncated: false)
    }

    public enum Error: Swift.Error, LocalizedError, Sendable, Equatable {
        case notRepository
        case gitFailed(String)
        case statusOutputTooLarge
        case malformedStatus
        case invalidStatusPath
        case indexTooLarge

        public var errorDescription: String? {
            switch self {
            case .notRepository: "The selected Resource is not a Git repository."
            case let .gitFailed(message): message
            case .statusOutputTooLarge: "Git status output exceeded the Host safety limit."
            case .malformedStatus: "Git returned malformed porcelain status output."
            case .invalidStatusPath: "Git returned an invalid repository-relative path."
            case .indexTooLarge: "The Git index exceeded the Host safety limit."
            }
        }
    }

    private func currentRepositoryRevision(at repositoryURL: URL) throws -> String {
        if let revision = try? runGit(["-C", repositoryURL.path, "rev-parse", "--verify", "HEAD"], maximumOutputBytes: 512),
           !revision.isEmpty {
            return revision
        }
        let branch = (try? runGit(["-C", repositoryURL.path, "symbolic-ref", "--quiet", "--short", "HEAD"], maximumOutputBytes: 512)) ?? "HEAD"
        return "unborn:\(branch)"
    }

    private func currentIndexRevision(at repositoryURL: URL) throws -> String {
        let path = try runGit(["-C", repositoryURL.path, "rev-parse", "--git-path", "index"], maximumOutputBytes: 4_096)
        let indexURL = URL(fileURLWithPath: path, relativeTo: repositoryURL).standardizedFileURL
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return digest(Data())
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: indexURL.path)
        guard let byteCount = attributes[.size] as? NSNumber, byteCount.int64Value <= Int64(Self.maximumIndexBytes) else {
            throw Error.indexTooLarge
        }
        return digest(try Data(contentsOf: indexURL, options: .mappedIfSafe))
    }

    private func parseStatus(_ output: Data, maximumEntries: Int) throws -> (entries: [RepositoryStatusSnapshot.Entry], truncated: Bool) {
        var entries: [RepositoryStatusSnapshot.Entry] = []
        var truncated = false
        let records = output.split(separator: 0, omittingEmptySubsequences: false)
        var index = 0

        while index < records.count {
            defer { index += 1 }
            let record = records[index]
            guard let kind = record.first else { continue }
            let parsedEntry: RepositoryStatusSnapshot.Entry?
            switch kind {
            case 35: // '#': porcelain-v2 header (not requested today, but safe to ignore).
                parsedEntry = nil
            case 49: // '1': ordinary changed entry.
                parsedEntry = try parseEntry(from: record, fieldCountBeforePath: 8)
            case 50: // '2': renamed/copied entry, followed by its original path.
                parsedEntry = try parseEntry(from: record, fieldCountBeforePath: 9)
                guard index + 1 < records.count else { throw Error.malformedStatus }
                index += 1
            case 117: // 'u': unmerged entry.
                parsedEntry = try parseEntry(from: record, fieldCountBeforePath: 10)
            case 63: // '?': untracked entry.
                let path = String(decoding: record.dropFirst(2), as: UTF8.self)
                parsedEntry = try statusEntry(path: path, indexStatus: "?", worktreeStatus: "?")
            case 33: // '!': ignored entry; never expose it in the normal status surface.
                parsedEntry = nil
            default:
                throw Error.malformedStatus
            }
            guard let parsedEntry else { continue }
            if entries.count < maximumEntries {
                entries.append(parsedEntry)
            } else {
                truncated = true
            }
        }
        return (entries, truncated)
    }

    private func parseEntry(from record: Data.SubSequence, fieldCountBeforePath: Int) throws -> RepositoryStatusSnapshot.Entry {
        let fields = record.split(separator: 32, maxSplits: fieldCountBeforePath, omittingEmptySubsequences: false)
        guard fields.count == fieldCountBeforePath + 1,
              let statuses = String(data: fields[1], encoding: .utf8), statuses.count == 2 else {
            throw Error.malformedStatus
        }
        let characters = Array(statuses)
        guard let path = String(data: fields[fieldCountBeforePath], encoding: .utf8) else { throw Error.invalidStatusPath }
        return try statusEntry(path: path, indexStatus: String(characters[0]), worktreeStatus: String(characters[1]))
    }

    private func statusEntry(path: String, indexStatus: String, worktreeStatus: String) throws -> RepositoryStatusSnapshot.Entry {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw Error.invalidStatusPath
        }
        return .init(path: path, indexStatus: indexStatus, worktreeStatus: worktreeStatus)
    }

    private func runGit(_ arguments: [String], maximumOutputBytes: Int) throws -> String {
        String(decoding: try runGitData(arguments, maximumOutputBytes: maximumOutputBytes), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGitData(_ arguments: [String], maximumOutputBytes: Int) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        var output = Data()
        while let chunk = try stdout.fileHandleForReading.read(upToCount: min(65_536, maximumOutputBytes - output.count + 1)), !chunk.isEmpty {
            output.append(chunk)
            if output.count > maximumOutputBytes {
                process.terminate()
                process.waitUntilExit()
                throw Error.statusOutputTooLarge
            }
        }
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Error.gitFailed(String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
