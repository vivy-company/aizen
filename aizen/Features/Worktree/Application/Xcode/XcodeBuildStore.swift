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
    @Published var isReady = false

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

    nonisolated static func persistenceKey(prefix: String, scopedTo path: String) -> String {
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
    var currentWorktreePath: String?
    var lastDestinationsRefreshAt: Date?
    let destinationsRefreshTTL: TimeInterval = 300

    init() {}

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
