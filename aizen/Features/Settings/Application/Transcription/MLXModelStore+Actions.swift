import Foundation
import os

extension MLXModelStore {
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
