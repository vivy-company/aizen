//
//  WorkflowService.swift
//  aizen
//
//  Observable service for managing CI/CD workflows
//

import Foundation
import Combine
import os.log

@MainActor
class WorkflowService: ObservableObject {
    // MARK: - Published State

    @Published var provider: WorkflowProvider = .none
    @Published var isLoading: Bool = false
    @Published var isInitializing: Bool = true  // Show loading on first load
    @Published var error: WorkflowError?

    @Published var workflows: [Workflow] = []
    @Published var runs: [WorkflowRun] = []
    @Published var selectedWorkflow: Workflow?
    @Published var selectedRun: WorkflowRun?
    @Published var selectedRunJobs: [WorkflowJob] = []
    @Published var runLogs: String = ""
    @Published var structuredLogs: WorkflowLogs?
    @Published var isLoadingLogs: Bool = false

    var currentLogJobId: String?

    @Published var cliAvailability: CLIAvailability?

    // MARK: - Private

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorkflowService")
    var repoPath: String = ""
    private var currentBranch: String = ""

    private var githubProvider: GitHubWorkflowProvider?
    private var gitlabProvider: GitLabWorkflowProvider?

    private var refreshTask: Task<Void, Never>?
    var logPollingTask: Task<Void, Never>?
    private var autoRefreshEnabled = false
    private var isStateStale = true

    private let runsLimit = 20

    // MARK: - Initialization

    func configure(repoPath: String, branch: String) async {
        let didChangeRepo = self.repoPath != repoPath
        self.repoPath = repoPath
        self.currentBranch = branch
        isInitializing = true
        isStateStale = true

        // Ensure shell environment is preloaded
        _ = ShellEnvironment.loadUserShellEnvironment()

        if didChangeRepo {
            stopAutoRefresh()
            stopLogPolling()
            clearSelection()
            workflows = []
            runs = []
            selectedRunJobs = []
            runLogs = ""
            structuredLogs = nil
            currentLogJobId = nil
        }

        // Detect provider
        let detectedProvider = await WorkflowDetector.shared.detect(repoPath: repoPath)
        provider = detectedProvider

        // Check CLI availability
        cliAvailability = await WorkflowDetector.shared.checkCLIAvailability()

        // Initialize appropriate provider
        switch detectedProvider {
        case .github:
            githubProvider = GitHubWorkflowProvider()
            gitlabProvider = nil
        case .gitlab:
            gitlabProvider = GitLabWorkflowProvider()
            githubProvider = nil
        case .none:
            githubProvider = nil
            gitlabProvider = nil
            break
        }

        isInitializing = false

        if autoRefreshEnabled {
            await refresh()
            startAutoRefresh()
        }
    }

    func updateBranch(_ branch: String) async {
        guard branch != currentBranch else { return }
        currentBranch = branch
        isStateStale = true
        guard autoRefreshEnabled else { return }
        await loadRuns()
    }

    // MARK: - Data Loading

    func loadWorkflows() async {
        guard provider != .none else { return }

        isLoading = true
        error = nil

        do {
            workflows = try await currentProvider?.listWorkflows(repoPath: repoPath) ?? []
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to load workflows: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to load workflows: \(error.localizedDescription)")
        }

        isLoading = false
        isStateStale = false
    }

    func loadRuns() async {
        guard provider != .none else { return }

        isLoading = true
        error = nil

        do {
            runs = try await currentProvider?.listRuns(
                repoPath: repoPath,
                workflow: nil,
                branch: currentBranch,
                limit: runsLimit
            ) ?? []
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to load runs: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to load runs: \(error.localizedDescription)")
        }

        isLoading = false
        isStateStale = false
    }

    func refresh() async {
        guard provider != .none else { return }
        await loadWorkflows()
        await loadRuns()

        // Refresh selected run if any
        if let selected = selectedRun {
            await selectRun(selected)
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
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

    // MARK: - Helpers

    var currentProvider: (any WorkflowProviderProtocol)? {
        switch provider {
        case .github: return githubProvider
        case .gitlab: return gitlabProvider
        case .none: return nil
        }
    }

    var isConfigured: Bool {
        provider != .none
    }

    var isCLIInstalled: Bool {
        guard let availability = cliAvailability else { return false }
        switch provider {
        case .github: return availability.gh
        case .gitlab: return availability.glab
        case .none: return false
        }
    }

    var isAuthenticated: Bool {
        guard let availability = cliAvailability else { return false }
        switch provider {
        case .github: return availability.ghAuthenticated
        case .gitlab: return availability.glabAuthenticated
        case .none: return false
        }
    }

    var installURL: URL? {
        switch provider {
        case .github: return URL(string: "https://cli.github.com")
        case .gitlab: return URL(string: "https://gitlab.com/gitlab-org/cli")
        case .none: return nil
        }
    }

    deinit {
        refreshTask?.cancel()
        logPollingTask?.cancel()
    }
}
