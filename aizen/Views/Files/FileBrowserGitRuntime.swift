//
//  FileBrowserGitRuntime.swift
//  aizen
//
//  Runtime helper for file browser git status and ignore data.
//

import Foundation
import os.log

struct FileBrowserGitSnapshot: Sendable {
    let fileStatus: [String: FileGitStatus]
    let ignoredPaths: Set<String>
}

actor FileBrowserGitRuntime {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "FileBrowserGitRuntime")

    func loadGitSnapshot(basePath: String, expandedPaths: Set<String>) async -> FileBrowserGitSnapshot {
        let fileStatus = await loadGitStatus(basePath: basePath)
        let ignoredPaths = await loadGitIgnoredPaths(basePath: basePath, expandedPaths: expandedPaths)
        return FileBrowserGitSnapshot(fileStatus: fileStatus, ignoredPaths: ignoredPaths)
    }

    private func loadGitStatus(basePath: String) async -> [String: FileGitStatus] {
        do {
            let status = try await Task.detached(priority: .utility) {
                let repo = try Libgit2Repository(path: basePath)
                return try repo.status()
            }.value

            var statusMap: [String: FileGitStatus] = [:]

            for entry in status.staged {
                let absolutePath = (basePath as NSString).appendingPathComponent(entry.path)
                statusMap[absolutePath] = .staged
            }

            for entry in status.modified {
                let absolutePath = (basePath as NSString).appendingPathComponent(entry.path)
                statusMap[absolutePath] = .modified
            }

            for entry in status.untracked {
                let absolutePath = (basePath as NSString).appendingPathComponent(entry.path)
                statusMap[absolutePath] = .untracked
            }

            for entry in status.conflicted {
                let absolutePath = (basePath as NSString).appendingPathComponent(entry.path)
                statusMap[absolutePath] = .conflicted
            }

            return statusMap
        } catch {
            logger.debug("Failed to load git status: \(error.localizedDescription)")
            return [:]
        }
    }

    private func loadGitIgnoredPaths(basePath: String, expandedPaths: Set<String>) async -> Set<String> {
        let pathsToCheck: [String] = await Task.detached(priority: .utility) {
            var paths: [String] = []

            if let items = try? FileManager.default.contentsOfDirectory(atPath: basePath) {
                paths.append(contentsOf: items)
            }

            for expandedPath in expandedPaths {
                let relativePath = expandedPath.hasPrefix(basePath)
                    ? String(expandedPath.dropFirst(basePath.count + 1))
                    : ""
                if let items = try? FileManager.default.contentsOfDirectory(atPath: expandedPath) {
                    for item in items {
                        let itemRelPath = relativePath.isEmpty ? item : "\(relativePath)/\(item)"
                        paths.append(itemRelPath)
                    }
                }
            }

            return paths
        }.value

        guard !pathsToCheck.isEmpty else { return [] }

        var ignoredPaths = Set<String>()
        let batchSize = 100
        for batchStart in stride(from: 0, to: pathsToCheck.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, pathsToCheck.count)
            let batch = Array(pathsToCheck[batchStart..<batchEnd])

            do {
                let result = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: ["check-ignore"] + batch,
                    workingDirectory: basePath
                )

                for line in result.stdout.split(separator: "\n") {
                    let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        ignoredPaths.insert(path)
                        let absolutePath = (basePath as NSString).appendingPathComponent(path)
                        ignoredPaths.insert(absolutePath)
                    }
                }
            } catch {
                logger.debug("git check-ignore failed: \(error.localizedDescription)")
            }
        }

        return ignoredPaths
    }
}
