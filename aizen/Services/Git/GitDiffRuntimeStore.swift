//
//  GitDiffRuntimeStore.swift
//  aizen
//
//  Shared working-diff runtime for a worktree.
//

import Combine
import Foundation

@MainActor
final class GitDiffRuntimeStore: ObservableObject {
    @Published private(set) var diffOutput: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isStale = true
    @Published private(set) var lastRefreshAt: Date?

    private let worktreePath: String

    private var isVisible = false
    private var isRefreshSuspended = false
    private var refreshTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(250)

    init(worktreePath: String) {
        self.worktreePath = worktreePath
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible {
            refreshTask?.cancel()
            refreshTask = nil
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
            return
        }

        if isStale || diffOutput.isEmpty {
            refresh(force: true)
        }
    }

    func setRefreshSuspended(_ suspended: Bool) {
        isRefreshSuspended = suspended
        if suspended {
            refreshTask?.cancel()
            refreshTask = nil
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
        } else if isVisible, (isStale || diffOutput.isEmpty) {
            refresh(force: true)
        }
    }

    func markStale() {
        isStale = true
    }

    func refresh(force: Bool = false) {
        guard isVisible, !isRefreshSuspended else { return }

        if force {
            refreshTask?.cancel()
            refreshTask = nil
            startLoad()
            return
        }

        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            do {
                try await Task.sleep(for: self.debounceInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.startLoad()
        }
    }

    private func startLoad() {
        let path = worktreePath
        guard !path.isEmpty else {
            if !diffOutput.isEmpty {
                diffOutput = ""
            }
            isLoading = false
            isStale = false
            lastRefreshAt = Date()
            return
        }

        loadTask?.cancel()
        isLoading = true

        loadTask = Task { [weak self] in
            guard let self else { return }
            let output = await Self.loadWorkingDiff(path: path)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.isVisible, !self.isRefreshSuspended else { return }
                if self.diffOutput != output {
                    self.diffOutput = output
                }
                self.isLoading = false
                self.isStale = false
                self.lastRefreshAt = Date()
            }
        }
    }

    nonisolated private static func loadWorkingDiff(path: String) async -> String {
        await Task.detached(priority: .utility) {
            do {
                let repo = try Libgit2Repository(path: path)

                let headDiff = try repo.diffUnified()
                if !headDiff.isEmpty {
                    return headDiff
                }

                let stagedDiff = try repo.diffStagedUnified()
                if !stagedDiff.isEmpty {
                    return stagedDiff
                }

                let unstagedDiff = try repo.diffUnstagedUnified()
                if !unstagedDiff.isEmpty {
                    return unstagedDiff
                }

                let status = try repo.status()
                if !status.untracked.isEmpty {
                    var output = ""
                    for entry in status.untracked.prefix(50) {
                        output += Self.buildFileDiff(file: entry.path, basePath: path)
                    }
                    return output
                }

                return ""
            } catch {
                return ""
            }
        }.value
    }

    nonisolated private static func buildFileDiff(file: String, basePath: String) -> String {
        let fullPath = (basePath as NSString).appendingPathComponent(file)
        guard let data = FileManager.default.contents(atPath: fullPath),
              let content = String(data: data, encoding: .utf8) else {
            return ""
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var parts = [String]()
        parts.reserveCapacity(lines.count + 5)

        parts.append("diff --git a/\(file) b/\(file)")
        parts.append("new file mode 100644")
        parts.append("--- /dev/null")
        parts.append("+++ b/\(file)")
        parts.append("@@ -0,0 +1,\(lines.count) @@")

        for line in lines {
            parts.append("+\(line)")
        }

        return parts.joined(separator: "\n") + "\n"
    }
}
