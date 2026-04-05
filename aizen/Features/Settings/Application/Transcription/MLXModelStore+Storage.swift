import Foundation

extension MLXModelStore {
    nonisolated static func directorySizeBytes(_ directory: URL) -> Int64 {
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
}
