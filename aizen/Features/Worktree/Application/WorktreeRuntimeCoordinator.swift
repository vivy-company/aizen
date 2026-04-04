import Foundation

@MainActor
final class WorktreeRuntimeCoordinator {
    static let shared = WorktreeRuntimeCoordinator()

    private var runtimes: [String: WorktreeRuntime] = [:]
    private var evictionTasks: [String: Task<Void, Never>] = [:]
    private let idleEvictionDelaySeconds: Double = 60

    private init() {}

    func runtime(for worktreePath: String) -> WorktreeRuntime {
        if let runtime = runtimes[worktreePath] {
            evictionTasks[worktreePath]?.cancel()
            evictionTasks[worktreePath] = nil
            return runtime
        }

        let runtime = WorktreeRuntime(worktreePath: worktreePath)
        runtime.setIdleStateHandler { [weak self] path, isIdle in
            guard let self else { return }
            if isIdle {
                self.scheduleEviction(for: path)
            } else {
                self.evictionTasks[path]?.cancel()
                self.evictionTasks[path] = nil
            }
        }
        runtimes[worktreePath] = runtime
        return runtime
    }

    private func scheduleEviction(for worktreePath: String) {
        evictionTasks[worktreePath]?.cancel()
        let idleDelay = idleEvictionDelaySeconds
        evictionTasks[worktreePath] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(idleDelay))
            } catch {
                return
            }
            await MainActor.run {
                self?.runtimes.removeValue(forKey: worktreePath)
                self?.evictionTasks.removeValue(forKey: worktreePath)
            }
        }
    }
}
