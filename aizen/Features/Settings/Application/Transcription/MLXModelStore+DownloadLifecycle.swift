import Foundation

extension MLXModelStore {
    func download(_ item: DownloadItem) async throws {
        activeItem = item
        let task = session.downloadTask(with: item.url)
        activeTask = task

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            activeContinuation = continuation
            task.resume()
        }
    }

    func updateProgress(currentFraction: Double) {
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
