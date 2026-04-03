//
//  XcodeBuildStore.swift
//  aizen
//
//  Xcode build and run management
//

import Foundation
import SwiftUI
import Combine
import os.log

@MainActor
final class XcodeBuildStore: ObservableObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeBuildStore")

    // MARK: - Published State

    @Published var currentPhase: BuildPhase = .idle
    @Published var detectedProject: XcodeProject?
    @Published var selectedScheme: String?
    @Published var selectedDestination: XcodeDestination?
    @Published var availableDestinations: [DestinationType: [XcodeDestination]] = [:]
    @Published var lastBuildLog: String?
    @Published var lastBuildDuration: TimeInterval?
    @Published var isLoadingDestinations = false
    @Published private(set) var isReady = false

    // Track launched app for termination before next launch
    @Published var launchedBundleId: String?
    @Published var launchedDestination: XcodeDestination?
    @Published var launchedAppPath: String?
    @Published var launchedPID: Int32?

    // For Mac apps launched directly, we keep the process and pipes to capture stdout/stderr
    var launchedProcess: Process?
    var launchedOutputPipe: Pipe?
    var launchedErrorPipe: Pipe?

    var appMonitorTask: Task<Void, Never>?

    // MARK: - Persistence

    nonisolated private static func persistenceKey(prefix: String, scopedTo path: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return "\(prefix)_\(normalizedPath)"
    }

    var lastDestinationIdKey: String {
        guard let path = currentWorktreePath else { return "" }
        return Self.persistenceKey(prefix: "xcodeLastDestinationId", scopedTo: path)
    }

    private var projectSchemeKey: String {
        guard let project = detectedProject else { return "" }
        return Self.persistenceKey(prefix: "xcodeScheme", scopedTo: project.path)
    }

    var destinationsCacheKey: String {
        guard let path = currentWorktreePath else { return "" }
        return Self.persistenceKey(prefix: "xcodeDestinationsCache", scopedTo: path)
    }

    // MARK: - Services

    let projectDetector = XcodeProjectDetector()
    let deviceService = XcodeDeviceService()
    private let buildService = XcodeBuildService()

    private var buildTask: Task<Void, Never>?
    private var currentWorktreePath: String?
    var lastDestinationsRefreshAt: Date?
    let destinationsRefreshTTL: TimeInterval = 300

    init() {}

    // MARK: - Detection

    func detectProject(at path: String) {
        if path == currentWorktreePath, detectedProject != nil {
            return
        }
        guard path != currentWorktreePath else { return }
        currentWorktreePath = path
        let projectDetector = self.projectDetector
        let destinationsCacheKey = self.destinationsCacheKey
        let lastDestinationIdKey = self.lastDestinationIdKey

        Task { [weak self] in
            guard let self = self else { return }

            // Reset state on main actor
            await MainActor.run {
                self.detectedProject = nil
                self.selectedScheme = nil
                self.currentPhase = .idle
                self.lastBuildLog = nil
                self.isReady = false
            }

            // Detect project off main actor
            let project = await projectDetector.detectProject(at: path)

            guard let project = project else {
                return  // isReady stays false
            }

            // Load cached destinations off main actor (JSON decoding)
            let cachedDestinations = Self.loadCachedDestinationsOffMainActor(from: destinationsCacheKey)
            let lastDestId = Self.loadLastDestinationId(from: lastDestinationIdKey)
            let savedScheme = self.loadSavedScheme(for: project.path)

            // Update UI state on main actor
            await MainActor.run {
                if let cached = cachedDestinations {
                    self.availableDestinations = cached
                }

                self.detectedProject = project

                // Restore or auto-select scheme
                if let saved = savedScheme, project.schemes.contains(saved) {
                    self.selectedScheme = saved
                } else {
                    self.selectedScheme = project.schemes.first
                }

                // Restore selected destination from cache
                if !lastDestId.isEmpty, let dest = self.findDestination(byId: lastDestId) {
                    self.selectedDestination = dest
                } else if self.selectedDestination == nil {
                    self.selectedDestination = self.availableDestinations[.simulator]?.first { $0.platform == "iOS" }
                        ?? self.availableDestinations[.mac]?.first
                }

                // Mark ready if we have cached destinations
                if !self.availableDestinations.isEmpty {
                    self.isReady = true
                }
            }

            // Refresh destinations in background (or load if no cache)
            let shouldRefresh = await MainActor.run { self.shouldRefreshDestinations(force: false) }
            if cachedDestinations != nil, shouldRefresh {
                await self.loadDestinations(force: false)
            } else {
                await self.loadDestinations(force: true)
                await MainActor.run {
                    self.isReady = true
                }
            }
        }
    }

    nonisolated private func loadSavedScheme(for projectPath: String) -> String? {
        let key = Self.persistenceKey(prefix: "xcodeScheme", scopedTo: projectPath)
        return UserDefaults.standard.string(forKey: key)
    }

    // MARK: - Scheme Selection

    func selectScheme(_ scheme: String) {
        selectedScheme = scheme
        guard !projectSchemeKey.isEmpty else { return }
        UserDefaults.standard.set(scheme, forKey: projectSchemeKey)
    }

    // MARK: - Destination Selection

    func selectDestination(_ destination: XcodeDestination) {
        selectedDestination = destination
        guard !lastDestinationIdKey.isEmpty else { return }
        UserDefaults.standard.set(destination.id, forKey: lastDestinationIdKey)
    }

    // MARK: - Build & Run

    func buildAndRun() {
        guard let project = detectedProject,
              let scheme = selectedScheme,
              let destination = selectedDestination else {
            logger.warning("Cannot build: missing project, scheme, or destination")
            return
        }

        // Cancel any existing build
        cancelBuild()

        let startTime = Date()
        let buildService = self.buildService

        buildTask = Task { [weak self] in
            guard let self = self else { return }

            for await phase in await buildService.buildAndRun(
                project: project,
                scheme: scheme,
                destination: destination
            ) {
                await MainActor.run {
                    self.currentPhase = phase

                    // Store log on failure
                    if case .failed(_, let log) = phase {
                        self.lastBuildLog = log
                        self.lastBuildDuration = Date().timeIntervalSince(startTime)
                    }

                    // Handle success
                    if case .succeeded = phase {
                        self.lastBuildDuration = Date().timeIntervalSince(startTime)
                        self.lastBuildLog = nil

                        // Launch app
                        if destination.type == .simulator {
                            Task {
                                await self.launchInSimulator(project: project, scheme: scheme, destination: destination)
                            }
                        } else if destination.type == .mac {
                            Task {
                                await self.launchOnMac(project: project, scheme: scheme)
                            }
                        } else if destination.type == .device {
                            Task {
                                await self.launchOnDevice(project: project, scheme: scheme, destination: destination)
                            }
                        }
                    }
                }
            }
        }
    }

    func cancelBuild() {
        buildTask?.cancel()
        buildTask = nil
        Task {
            await buildService.cancelBuild()
        }
        if currentPhase.isBuilding {
            currentPhase = .idle
        }
    }

    // MARK: - Reset

    func resetStatus() {
        if !currentPhase.isBuilding {
            currentPhase = .idle
            lastBuildLog = nil
        }
    }

    // MARK: - Log Streaming

    @Published var isLogStreamActive = false
    @Published var logOutput: [String] = []

    let logService = XcodeLogService()
    var logStreamTask: Task<Void, Never>?
    var macLogStreamTask: Task<Void, Never>?
}
