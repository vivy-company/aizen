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
    }

    private var entries: [String: Entry] = [:]

    func addSubscriber(worktreePath: String, onChange: @escaping @Sendable () -> Void) -> UUID {
        let key = worktreePath
        let id = UUID()

        if var entry = entries[key] {
            entry.subscribers[id] = onChange
            entries[key] = entry
            return id
        }

        let watcher = GitIndexWatcher(worktreePath: worktreePath)
        var entry = Entry(watcher: watcher, subscribers: [id: onChange])
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

    private func notifySubscribers(worktreePath: String) {
        guard let entry = entries[worktreePath] else { return }
        for callback in entry.subscribers.values {
            callback()
        }
    }
}

