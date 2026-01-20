//
//  GitIndexWatchCenter.swift
//  aizen
//
//  Shared coordinator for GitIndexWatcher to avoid duplicate polling per worktree.
//

import Foundation

actor GitIndexWatchCenter {
    static let shared = GitIndexWatchCenter()

    private struct Entry {
        let watcher: GitIndexWatcher
        var subscribers: [UUID: @MainActor @Sendable () -> Void]
        var pauseCount: Int
        var hasPendingNotification: Bool
    }

    private var entries: [String: Entry] = [:]
    private var pauseCounts: [String: Int] = [:]

    func addSubscriber(worktreePath: String, onChange: @escaping @MainActor @Sendable () -> Void) -> UUID {
        let key = worktreePath
        let id = UUID()

        if entries[key] != nil {
            entries[key]!.subscribers[id] = onChange
            return id
        }

        let watcher = GitIndexWatcher(worktreePath: worktreePath)
        let pauseCount = pauseCounts[key] ?? 0
        let entry = Entry(
            watcher: watcher,
            subscribers: [id: onChange],
            pauseCount: pauseCount,
            hasPendingNotification: false
        )
        entries[key] = entry

        watcher.startWatching { [worktreePath] in
            Task {
                await GitIndexWatchCenter.shared.notifySubscribers(worktreePath: worktreePath)
            }
        }

        return id
    }

    func removeSubscriber(worktreePath: String, id: UUID) {
        let key = worktreePath
        guard entries[key] != nil else { return }

        entries[key]!.subscribers.removeValue(forKey: id)
        if entries[key]!.subscribers.isEmpty {
            entries[key]!.watcher.stopWatching()
            entries.removeValue(forKey: key)
        }
    }

    func pause(worktreePath: String) {
        let key = worktreePath
        pauseCounts[key, default: 0] += 1
        if entries[key] != nil {
            entries[key]!.pauseCount += 1
        }
    }

    func resume(worktreePath: String) {
        let key = worktreePath
        guard let current = pauseCounts[key], current > 0 else { return }
        let newCount = current - 1
        if newCount == 0 {
            pauseCounts.removeValue(forKey: key)
        } else {
            pauseCounts[key] = newCount
        }

        guard entries[key] != nil else { return }
        entries[key]!.pauseCount = max(0, entries[key]!.pauseCount - 1)
        let shouldNotify = entries[key]!.pauseCount == 0 && entries[key]!.hasPendingNotification
        if shouldNotify {
            entries[key]!.hasPendingNotification = false
            let callbacks = entries[key]!.subscribers.values
            for callback in callbacks {
                Task { @MainActor in
                    callback()
                }
            }
        }
    }

    private func notifySubscribers(worktreePath: String) {
        guard entries[worktreePath] != nil else { return }
        if entries[worktreePath]!.pauseCount > 0 {
            entries[worktreePath]!.hasPendingNotification = true
            return
        }
        let callbacks = entries[worktreePath]!.subscribers.values
        for callback in callbacks {
            Task { @MainActor in
                callback()
            }
        }
    }
}
