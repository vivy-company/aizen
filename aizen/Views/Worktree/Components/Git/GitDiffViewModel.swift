//
//  GitDiffViewModel.swift
//  aizen
//
//  ViewModel for managing diff loading with caching and task cancellation
//

import SwiftUI
import Combine
import CryptoKit

@MainActor
class GitDiffViewModel: ObservableObject {
    @Published var loadedDiffs: [String: [DiffLine]] = [:]
    @Published var loadingFiles: Set<String> = []
    @Published var errors: [String: String] = [:]
    @Published var isBatchLoading: Bool = true
    var visibleFile: String? // Not @Published to avoid re-renders

    private let cache: GitDiffCache
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private let repoPath: String
    private let untrackedFiles: Set<String>

    init(repoPath: String, cache: GitDiffCache = GitDiffCache(), untrackedFiles: Set<String> = []) {
        self.repoPath = repoPath
        self.cache = cache
        self.untrackedFiles = untrackedFiles
    }

    func loadDiff(for file: String) {
        guard !loadingFiles.contains(file) else { return }
        guard loadedDiffs[file] == nil else { return }

        activeTasks[file]?.cancel()
        loadingFiles.insert(file)
        errors.removeValue(forKey: file)

        let isUntracked = untrackedFiles.contains(file)

        let task = Task { [weak self] in
            guard let self = self else { return }
            defer {
                Task { @MainActor in
                    self.activeTasks.removeValue(forKey: file)
                }
            }

            if let cached = await self.cache.getDiff(for: file) {
                await MainActor.run { [weak self] in
                    self?.loadedDiffs[file] = cached.lines
                    self?.loadingFiles.remove(file)
                }
                return
            }

            do {
                var lines: [DiffLine]

                if isUntracked {
                    // For untracked files, read file content and show as all additions
                    lines = await self.loadUntrackedFileAsDiff(file)
                } else {
                    // Use git command for formatted diff output
                    var diffOutput = await self.runGitDiff(["diff", "HEAD", "--", file])
                    if diffOutput == nil {
                        diffOutput = await self.runGitDiff(["diff", "--", file])
                    }
                    // Parse off the main actor to avoid blocking UI on large diffs
                    lines = await Task.detached(priority: .utility) {
                        DiffParser.parseUnifiedDiff(diffOutput ?? "")
                    }.value
                }

                guard !Task.isCancelled else { return }

                let hash = self.computeHash(file + String(lines.count))
                await self.cache.cacheDiff(lines, for: file, contentHash: hash)

                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.loadedDiffs[file] = lines
                    self?.loadingFiles.remove(file)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.errors[file] = error.localizedDescription
                    self?.loadingFiles.remove(file)
                }
            }
        }

        activeTasks[file] = task
    }

    func cancelLoad(for file: String) {
        activeTasks[file]?.cancel()
        activeTasks.removeValue(forKey: file)
        loadingFiles.remove(file)
    }

    func unloadDiff(for file: String) {
        loadedDiffs.removeValue(forKey: file)
    }

    func invalidateCache() async {
        await cache.invalidateAll()
        loadedDiffs.removeAll()
    }

    /// Batch load diffs for multiple files in a single git call
    func loadAllDiffs(for files: [String]) async {
        let trackedFiles = files.filter { !untrackedFiles.contains($0) }
        let filesToLoad = trackedFiles.filter { !loadedDiffs.keys.contains($0) && !loadingFiles.contains($0) }

        // Also load untracked files
        let untrackedToLoad = files.filter { untrackedFiles.contains($0) && !loadedDiffs.keys.contains($0) }

        guard !filesToLoad.isEmpty || !untrackedToLoad.isEmpty else {
            isBatchLoading = false
            return
        }

        do {
            // Load tracked files with single git diff
            if !filesToLoad.isEmpty {
                var diffOutput = await runGitDiff(["diff", "HEAD"])
                if diffOutput == nil {
                    diffOutput = await runGitDiff(["diff"])
                }

                // Parse off the main actor to avoid blocking UI on large diffs
                let parsedByFile = await Task.detached(priority: .utility) {
                    DiffParser.splitDiffByFile(diffOutput ?? "")
                }.value

                for file in filesToLoad {
                    let lines = parsedByFile[file] ?? []
                    loadedDiffs[file] = lines

                    if !lines.isEmpty {
                        let hash = computeHash(file + String(lines.count))
                        await cache.cacheDiff(lines, for: file, contentHash: hash)
                    }
                }
            }

            // Load untracked files
            for file in untrackedToLoad {
                let lines = await loadUntrackedFileAsDiff(file)
                loadedDiffs[file] = lines

                if !lines.isEmpty {
                    let hash = computeHash(file + String(lines.count))
                    await cache.cacheDiff(lines, for: file, contentHash: hash)
                }
            }

            isBatchLoading = false
        } catch {
            for file in filesToLoad {
                errors[file] = error.localizedDescription
            }
            isBatchLoading = false
        }
    }

    func invalidateFile(_ file: String) async {
        await cache.invalidate(file: file)
        loadedDiffs.removeValue(forKey: file)
    }

    private func computeHash(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func loadUntrackedFileAsDiff(_ file: String) async -> [DiffLine] {
        let fullPath = (repoPath as NSString).appendingPathComponent(file)

        // Read file on background thread to avoid blocking UI
        return await Task.detached {
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
                return [DiffLine]()
            }

            let fileLines = content.components(separatedBy: .newlines)
            var diffLines: [DiffLine] = []

            // Add header
            diffLines.append(DiffLine(
                lineNumber: 0,
                oldLineNumber: nil,
                newLineNumber: nil,
                content: "new file: \(file)",
                type: .header
            ))

            // Add all lines as additions
            for (index, line) in fileLines.enumerated() {
                diffLines.append(DiffLine(
                    lineNumber: index + 1,
                    oldLineNumber: nil,
                    newLineNumber: String(index + 1),
                    content: line,
                    type: .added
                ))
            }

            return diffLines
        }.value
    }

    /// Get unified diff output using libgit2
    private func runGitDiff(_ args: [String]) async -> String? {
        let path = repoPath

        // For single-file diffs, use the git CLI so we don't compute a full-repo diff.
        if args.contains("--") {
            do {
                let result = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: args,
                    workingDirectory: path
                )
                return result.succeeded ? result.stdout : nil
            } catch {
                return nil
            }
        }

        return await Task.detached(priority: .utility) {
            do {
                let repo = try Libgit2Repository(path: path)
                // Check if this is a HEAD diff or unstaged diff
                if args.contains("HEAD") {
                    return try repo.diffUnified()
                } else {
                    return try repo.diffUnstagedUnified()
                }
            } catch {
                return nil
            }
        }.value
    }

    deinit {
        for task in activeTasks.values {
            task.cancel()
        }
    }
}
