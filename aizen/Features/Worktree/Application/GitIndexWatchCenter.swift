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
    }

    private var entries: [String: Entry] = [:]

    func addSubscriber(worktreePath: String, onChange: @escaping @MainActor @Sendable () -> Void) -> UUID {
        let key = worktreePath
        let id = UUID()

        if entries[key] != nil {
            entries[key]!.subscribers[id] = onChange
            return id
        }

        let watcher = GitIndexWatcher(worktreePath: worktreePath)
        let entry = Entry(
            watcher: watcher,
            subscribers: [id: onChange]
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

    private func notifySubscribers(worktreePath: String) {
        guard entries[worktreePath] != nil else { return }
        let callbacks = entries[worktreePath]!.subscribers.values
        for callback in callbacks {
            Task { @MainActor in
                callback()
            }
        }
    }
}
