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
        var subscribers: [UUID: @Sendable () -> Void]
        var pauseCount: Int
        var hasPendingNotification: Bool
    }

    private var entries: [String: Entry] = [:]
    private var pauseCounts: [String: Int] = [:]

    func addSubscriber(worktreePath: String, onChange: @escaping @Sendable () -> Void) -> UUID {
        let key = worktreePath
        let id = UUID()

        if var entry = entries[key] {
            entry.subscribers[id] = onChange
            entries[key] = entry
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
        guard var entry = entries[key] else { return }

        entry.subscribers.removeValue(forKey: id)
        if entry.subscribers.isEmpty {
            entry.watcher.stopWatching()
            entries.removeValue(forKey: key)
        } else {
            entries[key] = entry
        }
    }

    func pause(worktreePath: String) {
        let key = worktreePath
        pauseCounts[key, default: 0] += 1
        if var entry = entries[key] {
            entry.pauseCount += 1
            entries[key] = entry
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

        guard var entry = entries[key] else { return }
        entry.pauseCount = max(0, entry.pauseCount - 1)
        let shouldNotify = entry.pauseCount == 0 && entry.hasPendingNotification
        entry.hasPendingNotification = false
        entries[key] = entry

        if shouldNotify {
            for callback in entry.subscribers.values {
                callback()
            }
        }
    }

    private func notifySubscribers(worktreePath: String) {
        guard var entry = entries[worktreePath] else { return }
        if entry.pauseCount > 0 {
            entry.hasPendingNotification = true
            entries[worktreePath] = entry
            return
        }
        for callback in entry.subscribers.values {
            callback()
        }
    }
}
