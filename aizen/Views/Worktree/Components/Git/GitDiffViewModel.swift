//
//  GitDiffViewModel.swift
//  aizen
//
//  ViewModel for managing diff loading with caching and task cancellation
//

import SwiftUI
import CryptoKit

@MainActor
class GitDiffViewModel: ObservableObject {
    @Published var loadedDiffs: [String: [DiffLine]] = [:]
    @Published var loadingFiles: Set<String> = []
    @Published var errors: [String: String] = [:]
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
                    let executor = GitCommandExecutor()
                    var diffOutput: String
                    do {
                        diffOutput = try await executor.executeGit(
                            arguments: ["diff", "HEAD", "--", file],
                            at: self.repoPath
                        )
                    } catch {
                        diffOutput = try await executor.executeGit(
                            arguments: ["diff", "--", file],
                            at: self.repoPath
                        )
                    }
                    lines = parseUnifiedDiff(diffOutput)
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
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return []
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
    }

    deinit {
        for task in activeTasks.values {
            task.cancel()
        }
    }
}
