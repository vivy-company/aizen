import Foundation

final class CachedValue<T> {
    private var value: T?
    private let fetch: () -> T
    private let duration: Duration
    private var expiryTask: Task<Void, Never>?

    init(duration: Duration, fetch: @escaping () -> T) {
        self.duration = duration
        self.fetch = fetch
    }

    deinit {
        expiryTask?.cancel()
    }

    func get() -> T {
        if let value {
            return value
        }

        let result = fetch()
        let expires = ContinuousClock.now + duration
        value = result

        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(until: expires)
                self?.value = nil
                self?.expiryTask = nil
            } catch {
            }
        }

        return result
    }
}
