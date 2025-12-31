//
//  GitIndexWatcher.swift
//  aizen
//
//  Monitors .git/index file and working directory for changes
//  Uses polling approach (more reliable than FSEvents for .git files)
//

import Foundation
import Darwin

nonisolated final class GitIndexWatcher: @unchecked Sendable {
    private let worktreePath: String
    private let gitIndexPath: String
    private let pollInterval: TimeInterval = 1.0  // Poll every 1 second
    private let debounceInterval: TimeInterval = 1.0  // Debounce rapid changes
    private var pollingTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var indexSource: DispatchSourceFileSystemObject?
    private var headSource: DispatchSourceFileSystemObject?
    private var indexFD: CInt = -1
    private var headFD: CInt = -1
    private let lastIndexModificationDateLock = NSLock()
    private var _lastIndexModificationDate: Date?
    private var lastIndexModificationDate: Date? {
        get {
            lastIndexModificationDateLock.lock()
            defer { lastIndexModificationDateLock.unlock() }
            return _lastIndexModificationDate
        }
        set {
            lastIndexModificationDateLock.lock()
            defer { lastIndexModificationDateLock.unlock() }
            _lastIndexModificationDate = newValue
        }
    }
    private let lastWorkdirChecksumLock = NSLock()
    private var _lastWorkdirChecksum: String?
    private var lastWorkdirChecksum: String? {
        get {
            lastWorkdirChecksumLock.lock()
            defer { lastWorkdirChecksumLock.unlock() }
            return _lastWorkdirChecksum
        }
        set {
            lastWorkdirChecksumLock.lock()
            defer { lastWorkdirChecksumLock.unlock() }
            _lastWorkdirChecksum = newValue
        }
    }
    private let onChangeLock = NSLock()
    private var _onChange: (@Sendable () -> Void)?
    private var onChange: (@Sendable () -> Void)? {
        get {
            onChangeLock.lock()
            defer { onChangeLock.unlock() }
            return _onChange
        }
        set {
            onChangeLock.lock()
            defer { onChangeLock.unlock() }
            _onChange = newValue
        }
    }
    private let pendingCallbackLock = NSLock()
    private var _hasPendingCallback = false
    private var hasPendingCallback: Bool {
        get {
            pendingCallbackLock.lock()
            defer { pendingCallbackLock.unlock() }
            return _hasPendingCallback
        }
        set {
            pendingCallbackLock.lock()
            defer { pendingCallbackLock.unlock() }
            _hasPendingCallback = newValue
        }
    }

    init(worktreePath: String) {
        self.worktreePath = worktreePath

        // Resolve .git path (handles linked worktrees)
        let gitPath = (worktreePath as NSString).appendingPathComponent(".git")

        // Check if .git is a file (linked worktree) or directory
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            // Linked worktree - .git is a file containing gitdir path
            if let gitContent = try? String(contentsOfFile: gitPath, encoding: .utf8),
               gitContent.hasPrefix("gitdir: ") {
                let gitdir = gitContent
                    .replacingOccurrences(of: "gitdir: ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // gitdir points to .git/worktrees/<name>
                // The index is at .git/worktrees/<name>/index (not worktree/.git/index)
                self.gitIndexPath = (gitdir as NSString).appendingPathComponent("index")
            } else {
                // Fallback if we can't parse
                self.gitIndexPath = (worktreePath as NSString).appendingPathComponent(".git/index")
            }
        } else {
            // Primary worktree - standard .git/index path
            self.gitIndexPath = (worktreePath as NSString).appendingPathComponent(".git/index")
        }
    }

    func startWatching(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        guard FileManager.default.fileExists(atPath: gitIndexPath) else {
            return
        }

        // Get initial modification dates (cheap file stats only)
        lastIndexModificationDate = try? FileManager.default.attributesOfItem(atPath: gitIndexPath)[.modificationDate] as? Date

        // Get initial HEAD modification date
        let headPath = (gitIndexPath as NSString).deletingLastPathComponent
        let headFilePath = (headPath as NSString).appendingPathComponent("HEAD")
        if let headAttrs = try? FileManager.default.attributesOfItem(atPath: headFilePath),
           let headModDate = headAttrs[.modificationDate] as? Date {
            lastWorkdirChecksum = String(headModDate.timeIntervalSince1970)
        }

        if !setupDispatchSources() {
            // Start polling task on BACKGROUND thread (fallback)
            // Only monitor index file changes - avoid expensive git status calls
            // that can contend with libgit2 operations
            pollingTask = Task.detached { [weak self] in
                guard let self = self else { return }

                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(self.pollInterval))

                        guard !Task.isCancelled else { break }

                        var hasChanges = false

                        // Check if index was modified (cheap file stat)
                        // This detects: staging, unstaging, commits, branch switches, etc.
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: self.gitIndexPath),
                           let modDate = attrs[.modificationDate] as? Date {

                            if let lastDate = self.lastIndexModificationDate, modDate > lastDate {
                                self.lastIndexModificationDate = modDate
                                hasChanges = true
                            } else if self.lastIndexModificationDate == nil {
                                self.lastIndexModificationDate = modDate
                            }
                        }

                        // Also check HEAD file for branch switches
                        let headPath = (self.gitIndexPath as NSString).deletingLastPathComponent
                        let headFilePath = (headPath as NSString).appendingPathComponent("HEAD")
                        if let headAttrs = try? FileManager.default.attributesOfItem(atPath: headFilePath),
                           let headModDate = headAttrs[.modificationDate] as? Date {

                            if let lastDate = self.lastWorkdirChecksum.flatMap({ Double($0) }).map({ Date(timeIntervalSince1970: $0) }),
                               headModDate > lastDate {
                                self.lastWorkdirChecksum = String(headModDate.timeIntervalSince1970)
                                hasChanges = true
                            } else if self.lastWorkdirChecksum == nil {
                                self.lastWorkdirChecksum = String(headModDate.timeIntervalSince1970)
                            }
                        }

                        if hasChanges {
                            self.scheduleDebounceCallback()
                        }
                    } catch {
                        break
                    }
                }
            }
        }
    }

    func stopWatching() {
        pollingTask?.cancel()
        pollingTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        indexSource?.cancel()
        headSource?.cancel()
        indexSource = nil
        headSource = nil
        if indexFD != -1 {
            close(indexFD)
            indexFD = -1
        }
        if headFD != -1 {
            close(headFD)
            headFD = -1
        }
        onChange = nil
        lastIndexModificationDate = nil
        lastWorkdirChecksum = nil
        hasPendingCallback = false
    }

    private func setupDispatchSources() -> Bool {
        let headPath = (gitIndexPath as NSString).deletingLastPathComponent
        let headFilePath = (headPath as NSString).appendingPathComponent("HEAD")

        indexFD = open(gitIndexPath, O_EVTONLY)
        headFD = open(headFilePath, O_EVTONLY)

        var createdSource = false

        if indexFD != -1 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: indexFD,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.scheduleDebounceCallback()
            }
            source.setCancelHandler { [weak self] in
                if let fd = self?.indexFD, fd != -1 {
                    close(fd)
                    self?.indexFD = -1
                }
            }
            source.resume()
            indexSource = source
            createdSource = true
        }

        if headFD != -1 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: headFD,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.scheduleDebounceCallback()
            }
            source.setCancelHandler { [weak self] in
                if let fd = self?.headFD, fd != -1 {
                    close(fd)
                    self?.headFD = -1
                }
            }
            source.resume()
            headSource = source
            createdSource = true
        }

        if !createdSource {
            if indexFD != -1 {
                close(indexFD)
                indexFD = -1
            }
            if headFD != -1 {
                close(headFD)
                headFD = -1
            }
        }

        return createdSource
    }

    private func scheduleDebounceCallback() {
        // If already pending, the existing debounce will fire
        guard !hasPendingCallback else { return }
        hasPendingCallback = true

        // Cancel any existing debounce task
        debounceTask?.cancel()

        debounceTask = Task.detached { [weak self] in
            guard let self = self else { return }

            // Wait for debounce interval
            do {
                try await Task.sleep(for: .seconds(self.debounceInterval))
            } catch {
                return  // Cancelled
            }

            guard !Task.isCancelled else { return }

            // Clear pending flag and fire callback
            self.hasPendingCallback = false
            self.onChange?()
        }
    }

}
