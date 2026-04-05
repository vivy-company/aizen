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

    @Published var state: DownloadState = .idle
    @Published var localStorageBytes: Int64 = 0
    @Published var totalStorageBytes: Int64 = 0
    @Published var repoSizeBytes: Int64?
    @Published var modelId: String {
        didSet {
            refreshStatus()
        }
    }

    let kind: MLXModelKind

    private let logger = Logger.settings
    var session: URLSession!
    var activeTask: URLSessionDownloadTask?
    var activeItem: DownloadItem?
    var activeContinuation: CheckedContinuation<URL, Error>?
    var completedCount = 0
    var totalCount = 0
    var storageTask: Task<Void, Never>?
    var repoSizeTask: Task<Void, Never>?
    var lastRepoSizeModelId: String?

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

}
