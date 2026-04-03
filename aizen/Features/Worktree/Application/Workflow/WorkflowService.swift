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
    var currentBranch: String = ""

    private var githubProvider: GitHubWorkflowProvider?
    private var gitlabProvider: GitLabWorkflowProvider?

    var refreshTask: Task<Void, Never>?
    var logPollingTask: Task<Void, Never>?
    var autoRefreshEnabled = false
    var isStateStale = true

    let runsLimit = 20

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
