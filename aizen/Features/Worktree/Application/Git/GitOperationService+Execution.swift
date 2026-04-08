import Foundation
import os.log

@MainActor
extension GitOperationService {
    func makeRefreshingSuccessHandler(original: (() -> Void)?) -> (() async -> Void) {
        return { [weak self] in
            guard let self else {
                await MainActor.run { original?() }
                return
            }
            await MainActor.run {
                self.onMutationCompleted()
                original?()
            }
        }
    }

    func makeMutationOnlySuccessHandler() -> (() async -> Void) {
        return { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.onMutationCompleted()
            }
        }
    }

    func enqueueOperation<T>(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) async -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            await self.executeOperationBackground(operation, onSuccess: onSuccess, onError: onError)
        }
    }

    func executeOperationBackground<T>(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) async -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) async {
        await MainActor.run {
            self.isOperationPending = true
        }

        do {
            let result = try await operation()
            if let onSuccess {
                await onSuccess(result)
            }
        } catch {
            await MainActor.run {
                onError?(error)
            }
            logger.error("Git operation failed: \(error.localizedDescription)")
        }

        await MainActor.run {
            self.isOperationPending = false
        }
    }
}
