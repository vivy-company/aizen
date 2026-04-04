//
//  GitIndexWatcher+Debounce.swift
//  aizen
//
//  Debounced callback delivery for git index watcher events
//

import Foundation

extension GitIndexWatcher {
    nonisolated func scheduleDebounceCallback() {
        guard !hasPendingCallback else { return }
        hasPendingCallback = true

        debounceTask?.cancel()

        debounceTask = Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                try await Task.sleep(for: .seconds(self.debounceInterval))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            self.hasPendingCallback = false
            self.onChange?()
        }
    }
}
