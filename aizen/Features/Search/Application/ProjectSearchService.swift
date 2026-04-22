import Foundation

actor ProjectSearchService {
    static let shared = ProjectSearchService()

    private let registry = FFFInstanceRegistry()
    private let fileService = FileService()
    private let maxPreviewBytes = 1_000_000

    func searchFiles(
        query: String,
        worktreePath: String,
        limit: Int = 60
    ) async throws -> ProjectFileSearchResponse {
        let client = try await registry.client(for: worktreePath)
        return try await Task.detached(priority: .userInitiated) {
            try client.searchFiles(query: query, limit: limit)
        }.value
    }

    func searchContent(
        query: String,
        grepMode: ProjectSearchGrepMode,
        worktreePath: String,
        limit: Int = 60,
        fileOffset: Int = 0
    ) async throws -> ProjectContentSearchResponse {
        let client = try await registry.client(for: worktreePath)
        return try await Task.detached(priority: .userInitiated) {
            try client.liveGrep(query: query, mode: grepMode, limit: limit, fileOffset: fileOffset)
        }.value
    }

    func scanProgress(worktreePath: String) async throws -> ProjectSearchStatus {
        let client = try await registry.client(for: worktreePath)
        return try await Task.detached(priority: .utility) {
            try client.scanProgress()
        }.value
    }

    func refreshGitStatus(worktreePath: String) async {
        do {
            let client = try await registry.client(for: worktreePath)
            try await Task.detached(priority: .utility) {
                try client.refreshGitStatus()
            }.value
        } catch {
            print("ProjectSearchService.refreshGitStatus failed: \(error)")
        }
    }

    func trackSelection(query: String, selectedPath: String, worktreePath: String) async {
        do {
            let client = try await registry.client(for: worktreePath)
            try await Task.detached(priority: .utility) {
                try client.trackQuery(query, selectedPath: selectedPath)
            }.value
        } catch {
            print("ProjectSearchService.trackSelection failed: \(error)")
        }
    }

    func loadPreview(for result: ProjectSearchResult) async -> ProjectSearchPreviewState {
        let path = result.path
        let fileURL = URL(fileURLWithPath: path)

        if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > maxPreviewBytes {
            let mb = Double(size) / 1_000_000
            return .unavailable(String(format: "Preview unavailable for files larger than %.1f MB.", mb))
        }

        do {
            let content = try await fileService.readFile(path: path)
            return .loaded(
                ProjectSearchPreview(
                    path: path,
                    relativePath: result.relativePath,
                    content: content,
                    openRequest: result.openRequest.hasLocation ? result.openRequest : nil
                )
            )
        } catch {
            return .unavailable("Unable to load a text preview for this file.")
        }
    }
}
