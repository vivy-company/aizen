import AizenCore
import AizenStorage
import CryptoKit
import Foundation

/// Resolves filesystem access inside Host-owned execution-context roots.
public actor ExecutionContextFileService {
    public enum Error: Swift.Error, Sendable, Equatable {
        case unknownContext(ExecutionContextID)
        case unavailableContext(ExecutionContextID)
        case invalidRelativePath(String)
        case pathEscapesContext(String)
        case notDirectory(String)
        case notFile(String)
        case fileTooLarge(String)
        case invalidText(String)
        case sensitivePath(String)
        case revisionConflict
        case invalidSearchQuery
    }

    private let storage: StorageRepository
    private let fileManager: FileManager

    public init(storage: StorageRepository, fileManager: FileManager = .default) {
        self.storage = storage
        self.fileManager = fileManager
    }

    public func listDirectory(contextID: ExecutionContextID, relativePath: String = "", includeHidden: Bool = false) async throws -> [ContextFileEntry] {
        let root = try await contextRoot(contextID)
        let directory = try resolvedChild(relativePath, root: root)
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Error.notDirectory(relativePath)
        }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: includeHidden ? [] : [.skipsHiddenFiles])
            .compactMap { url -> ContextFileEntry? in
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else { return nil }
                let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey])
                let relativePath = String(resolved.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !Self.isSensitive(relativePath) else { return nil }
                return ContextFileEntry(
                    relativePath: relativePath,
                    name: url.lastPathComponent,
                    isDirectory: values?.isDirectory == true
                )
            }
            .sorted { ($0.isDirectory == $1.isDirectory) ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : $0.isDirectory }
    }

    public func readTextFile(contextID: ExecutionContextID, relativePath: String) async throws -> String {
        guard !Self.isSensitive(relativePath) else { throw Error.sensitivePath(relativePath) }
        let root = try await contextRoot(contextID)
        let file = try resolvedChild(relativePath, root: root)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Error.notFile(relativePath) }
        guard (values.fileSize ?? 0) <= Self.maximumTextFileBytes else { throw Error.fileTooLarge(relativePath) }
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        guard let text = String(data: data, encoding: .utf8) else { throw Error.invalidText(relativePath) }
        return text
    }

    /// Searches only regular UTF-8 files that stay inside the execution-context root. Hidden,
    /// sensitive, binary, and oversized files are intentionally not observable through search.
    public func searchText(
        contextID: ExecutionContextID,
        query: String,
        maximumMatches: Int
    ) async throws -> ContextFileSearchResult {
        guard !query.isEmpty,
              query.utf8.count <= Self.maximumSearchQueryUTF8Count,
              (1...Self.maximumSearchMatches).contains(maximumMatches) else {
            throw Error.invalidSearchQuery
        }
        let root = try await contextRoot(contextID)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw Error.unavailableContext(contextID)
        }

        var matches: [ContextFileSearchMatch] = []
        var filesExamined = 0
        var truncated = false
        while let candidate = enumerator.nextObject() as? URL {
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/") else {
                enumerator.skipDescendants()
                continue
            }
            let relativePath = String(resolved.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !Self.isSensitive(relativePath) else {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else { continue }
            guard values.isRegularFile == true else { continue }
            guard (values.fileSize ?? 0) <= Self.maximumTextFileBytes else { continue }
            guard filesExamined < Self.maximumSearchFiles else {
                truncated = true
                break
            }
            filesExamined += 1
            guard let text = try? String(contentsOf: resolved, encoding: .utf8) else { continue }

            for (offset, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
                guard line.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                matches.append(.init(relativePath: relativePath, lineNumber: offset + 1, preview: Self.preview(for: line)))
                if matches.count == maximumMatches {
                    truncated = true
                    return .init(matches: matches, truncated: truncated)
                }
            }
        }
        return .init(matches: matches, truncated: truncated)
    }

    /// Rechecks the expected SHA-256 while this actor owns the file operation, then replaces
    /// only a regular context-relative UTF-8 file using Foundation's atomic write.
    public func replaceTextFile(contextID: ExecutionContextID, relativePath: String, expectedContentHash: String, text: String) async throws -> String {
        guard !Self.isSensitive(relativePath) else { throw Error.sensitivePath(relativePath) }
        let root = try await contextRoot(contextID)
        let file = try resolvedChild(relativePath, root: root)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Error.notFile(relativePath) }
        guard (values.fileSize ?? 0) <= Self.maximumTextFileBytes else { throw Error.fileTooLarge(relativePath) }
        let existing = try Data(contentsOf: file, options: [.mappedIfSafe])
        guard Self.contentHash(existing) == expectedContentHash else { throw Error.revisionConflict }
        let replacement = Data(text.utf8)
        guard replacement.count <= Self.maximumTextFileBytes else { throw Error.fileTooLarge(relativePath) }
        try replacement.write(to: file, options: .atomic)
        return Self.contentHash(replacement)
    }

    private static let maximumTextFileBytes = 1_048_576
    private static let maximumSearchQueryUTF8Count = 256
    private static let maximumSearchMatches = 100
    private static let maximumSearchFiles = 1_000

    private static func preview(for line: Substring) -> String {
        String(decoding: String(line).utf8.prefix(ContextFileSearchMatch.maximumPreviewUTF8Count), as: UTF8.self)
    }

    private static func contentHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func contextRoot(_ contextID: ExecutionContextID) async throws -> URL {
        let snapshot = try await storage.load()
        guard let context = snapshot.executionContexts.first(where: { $0.id == contextID }) else { throw Error.unknownContext(contextID) }
        guard let reference = context.hostReference?.rawValue else { throw Error.unavailableContext(contextID) }
        let prefixes = ["local-worktree:", "local-checkout:", "local-independent:"]
        guard let prefix = prefixes.first(where: { reference.hasPrefix($0) }) else { throw Error.unavailableContext(contextID) }
        let root = URL(fileURLWithPath: String(reference.dropFirst(prefix.count))).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw Error.unavailableContext(contextID) }
        return root
    }

    private func resolvedChild(_ relativePath: String, root: URL) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard relativePath.isEmpty || (
            !relativePath.contains("\0") &&
            !relativePath.hasPrefix("/") &&
            !relativePath.hasSuffix("/") &&
            !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        ) else {
            throw Error.invalidRelativePath(relativePath)
        }
        let child = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard child.path == root.path || child.path.hasPrefix(root.path + "/") else { throw Error.pathEscapesContext(relativePath) }
        return child
    }

    private static func isSensitive(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { component in
            let name = component.lowercased()
            return name == ".ssh" || name == ".aizen" || name == ".env" || name.hasPrefix(".env.") ||
                name == "id_rsa" || name == "id_ed25519" || name == "authorized_keys" ||
                name.contains("credential") || name.hasSuffix(".pem") || name.hasSuffix(".key") || name.hasSuffix(".p12")
        }
    }
}
