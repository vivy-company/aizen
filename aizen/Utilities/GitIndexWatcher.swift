//
//  GitIndexWatcher.swift
//  aizen
//
//  Monitors .git/index file and working directory for changes
//  Uses polling approach (more reliable than FSEvents for .git files)
//

import Foundation

class GitIndexWatcher {
    private let worktreePath: String
    private let gitIndexPath: String
    private let pollInterval: TimeInterval = 1.0  // Poll every 1 second
    private var pollingTask: Task<Void, Never>?
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

        // Get initial modification date and checksum
        lastIndexModificationDate = try? FileManager.default.attributesOfItem(atPath: gitIndexPath)[.modificationDate] as? Date
        lastWorkdirChecksum = computeWorkdirChecksum()

        // Start polling task on BACKGROUND thread
        pollingTask = Task.detached { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))

                    guard !Task.isCancelled else { break }

                    var hasChanges = false

                    // Check if index was modified
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: self.gitIndexPath),
                       let modDate = attrs[.modificationDate] as? Date {

                        if let lastDate = self.lastIndexModificationDate, modDate > lastDate {
                            self.lastIndexModificationDate = modDate
                            hasChanges = true
                        } else if self.lastIndexModificationDate == nil {
                            self.lastIndexModificationDate = modDate
                        }
                    }

                    // Check if working directory changed
                    let currentChecksum = self.computeWorkdirChecksum()
                    if currentChecksum != self.lastWorkdirChecksum {
                        self.lastWorkdirChecksum = currentChecksum
                        hasChanges = true
                    }

                    if hasChanges {
                        self.onChange?()
                    }
                } catch {
                    break
                }
            }
        }
    }

    func stopWatching() {
        pollingTask?.cancel()
        pollingTask = nil
        onChange = nil
        lastIndexModificationDate = nil
        lastWorkdirChecksum = nil
    }

    private func computeWorkdirChecksum() -> String {
        // Get git status output hash to detect working directory changes
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = URL(fileURLWithPath: worktreePath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
