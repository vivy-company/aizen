import Foundation
import Combine
import os.log

enum MLXModelKind: String, CaseIterable, Identifiable {
    case whisper
    case parakeetTDT

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper:
            return "MLX Whisper"
        case .parakeetTDT:
            return "MLX Parakeet"
        }
    }

    var folderName: String {
        switch self {
        case .whisper:
            return "whisper"
        case .parakeetTDT:
            return "parakeet-tdt"
        }
    }
}

@MainActor
final class MLXModelStore: NSObject, ObservableObject {
    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    @Published private(set) var state: DownloadState = .idle
    @Published private(set) var localStorageBytes: Int64 = 0
    @Published private(set) var totalStorageBytes: Int64 = 0
    @Published private(set) var repoSizeBytes: Int64?
    @Published var modelId: String {
        didSet {
            refreshStatus()
        }
    }

    let kind: MLXModelKind

    private let logger = Logger.settings
    var session: URLSession!
    private var activeTask: URLSessionDownloadTask?
    private var activeItem: DownloadItem?
    private var activeContinuation: CheckedContinuation<URL, Error>?
    private var completedCount = 0
    private var totalCount = 0
    private var storageTask: Task<Void, Never>?
    private var repoSizeTask: Task<Void, Never>?
    private var lastRepoSizeModelId: String?

    init(kind: MLXModelKind, modelId: String) {
        self.kind = kind
        self.modelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    struct HFModelInfo: Decodable {
        let siblings: [HFSibling]
        let usedStorage: Int64?
    }

    struct HFSibling: Decodable {
        let rfilename: String
    }

    struct SafetensorsIndex: Decodable {
        let weightMap: [String: String]

        enum CodingKeys: String, CodingKey {
            case weightMap = "weight_map"
        }
    }

    struct DownloadItem {
        let url: URL
        let destination: URL
    }

    var modelDirectory: URL {
        Self.modelDirectory(for: kind, modelId: normalizedModelId)
    }

    static var modelsRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".aizen", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    var isModelAvailable: Bool {
        Self.isModelAvailable(kind: kind, modelId: normalizedModelId)
    }

    func refreshStatus() {
        if isModelAvailable {
            state = .ready
        } else if case .downloading = state {
            return
        } else {
            state = .idle
        }
        refreshStorageUsage()
        refreshRepoSize()
    }

    func removeModel() {
        do {
            if FileManager.default.fileExists(atPath: modelDirectory.path) {
                try FileManager.default.removeItem(at: modelDirectory)
            }
            state = .idle
            refreshStorageUsage()
        } catch {
            logger.error("Failed to remove MLX model: \(error.localizedDescription)")
            state = .failed("Failed to remove model")
        }
    }

    func downloadModel() async {
        if case .downloading = state { return }

        let modelId = normalizedModelId
        guard !modelId.isEmpty else {
            state = .failed("Model ID is required")
            return
        }

        do {
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

            let items = try await resolveDownloadItems()

            completedCount = 0
            totalCount = items.count
            state = .downloading(progress: 0)

            for item in items {
                try await download(item)
                completedCount += 1
                updateProgress(currentFraction: 0)
            }

            state = .ready
            refreshStorageUsage()
        } catch {
            logger.error("Failed to download MLX model: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    static func isModelAvailable(kind: MLXModelKind, modelId: String) -> Bool {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let directory = modelDirectory(for: kind, modelId: normalized)
        let config = directory.appendingPathComponent("config.json")
        let weights = weightFiles(in: directory)
        return FileManager.default.fileExists(atPath: config.path) && !weights.isEmpty
    }

    static func modelDirectory(for kind: MLXModelKind, modelId: String) -> URL {
        let sanitized = sanitizeModelId(modelId)
        return modelsRoot
            .appendingPathComponent(kind.folderName, isDirectory: true)
            .appendingPathComponent(sanitized, isDirectory: true)
    }

    static func weightFiles(in directory: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let allowedExtensions = Set(["safetensors", "npz"])
        return files.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
    }

    var normalizedModelId: String {
        modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeModelId(_ modelId: String) -> String {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.isEmpty ? "unknown-model" : trimmed
        return collapsed.replacingOccurrences(of: "/", with: "--")
    }

    nonisolated private static func directorySizeBytes(_ directory: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    func refreshStorageUsage() {
        storageTask?.cancel()
        let modelDir = modelDirectory
        let rootDir = Self.modelsRoot
        storageTask = Task.detached { [weak self] in
            let modelBytes = Self.directorySizeBytes(modelDir)
            let rootBytes = Self.directorySizeBytes(rootDir)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.localStorageBytes = modelBytes
                self.totalStorageBytes = rootBytes
            }
        }
    }

    func refreshRepoSize() {
        let modelId = normalizedModelId
        guard !modelId.isEmpty else {
            repoSizeBytes = nil
            return
        }
        if lastRepoSizeModelId == modelId, repoSizeBytes != nil {
            return
        }
        repoSizeTask?.cancel()
        lastRepoSizeModelId = modelId
        repoSizeBytes = nil
        repoSizeTask = Task.detached { [weak self] in
            let size = await MLXModelSizeCache.shared.size(for: modelId)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.repoSizeBytes = size
            }
        }
    }

    private func download(_ item: DownloadItem) async throws {
        activeItem = item
        let task = session.downloadTask(with: item.url)
        activeTask = task

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            activeContinuation = continuation
            task.resume()
        }
    }

    private func updateProgress(currentFraction: Double) {
        guard totalCount > 0 else { return }
        let completed = Double(completedCount)
        let progress = (completed + currentFraction) / Double(totalCount)
        state = .downloading(progress: min(max(progress, 0), 1))
    }
}

extension MLXModelStore: @preconcurrency URLSessionDownloadDelegate {
    @MainActor
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let item = activeItem else { return }
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            let status = response.statusCode
            activeContinuation?.resume(throwing: NSError(
                domain: "MLXModelStore",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "Download failed with status \(status)"]
            ))
            activeContinuation = nil
            activeTask = nil
            activeItem = nil
            return
        }
        do {
            if FileManager.default.fileExists(atPath: item.destination.path) {
                try FileManager.default.removeItem(at: item.destination)
            }
            try FileManager.default.moveItem(at: location, to: item.destination)
            activeContinuation?.resume(returning: item.destination)
        } catch {
            activeContinuation?.resume(throwing: error)
        }
        activeContinuation = nil
        activeTask = nil
        activeItem = nil
    }

    @MainActor
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.updateProgress(currentFraction: fraction)
        }
    }

    @MainActor
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            activeContinuation?.resume(throwing: error)
            activeContinuation = nil
            activeTask = nil
            activeItem = nil
        }
    }
}
