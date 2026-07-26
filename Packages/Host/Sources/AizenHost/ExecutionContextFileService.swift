import AizenCore
import AizenStorage
import Foundation

/// Resolves filesystem access inside Host-owned execution-context roots.
public actor ExecutionContextFileService {
    public enum Error: Swift.Error, Sendable, Equatable {
        case unknownContext(ExecutionContextID)
        case unavailableContext(ExecutionContextID)
        case invalidRelativePath(String)
        case pathEscapesContext(String)
        case notDirectory(String)
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
                return ContextFileEntry(
                    relativePath: String(resolved.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                    name: url.lastPathComponent,
                    isDirectory: values?.isDirectory == true
                )
            }
            .sorted { ($0.isDirectory == $1.isDirectory) ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : $0.isDirectory }
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
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else { throw Error.invalidRelativePath(relativePath) }
        let child = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard child.path == root.path || child.path.hasPrefix(root.path + "/") else { throw Error.pathEscapesContext(relativePath) }
        return child
    }
}
