//
//  WorkflowService+AutoRefresh.swift
//  aizen
//
//  Auto-refresh scheduling and lifecycle.
//

import Foundation

@MainActor
extension WorkflowService {
    func startAutoRefresh() {
        stopAutoRefresh()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        guard isConfigured else { return }
        autoRefreshEnabled = enabled
        if enabled {
            if isStateStale || workflows.isEmpty || runs.isEmpty {
                Task { [weak self] in
                    await self?.refresh()
                }
            }
            startAutoRefresh()
        } else {
            stopAutoRefresh()
            stopLogPolling()
        }
    }
}
