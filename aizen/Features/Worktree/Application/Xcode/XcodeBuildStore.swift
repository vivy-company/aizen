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

    private var lastDestinationIdKey: String {
        guard let path = currentWorktreePath else { return "" }
        return Self.persistenceKey(prefix: "xcodeLastDestinationId", scopedTo: path)
    }

    private var projectSchemeKey: String {
        guard let project = detectedProject else { return "" }
        return Self.persistenceKey(prefix: "xcodeScheme", scopedTo: project.path)
    }

    private var destinationsCacheKey: String {
        guard let path = currentWorktreePath else { return "" }
        return Self.persistenceKey(prefix: "xcodeDestinationsCache", scopedTo: path)
    }

    // MARK: - Services

    let projectDetector = XcodeProjectDetector()
    let deviceService = XcodeDeviceService()
    private let buildService = XcodeBuildService()

    private var buildTask: Task<Void, Never>?
    private var currentWorktreePath: String?
    private var lastDestinationsRefreshAt: Date?
    private let destinationsRefreshTTL: TimeInterval = 300

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

    /// Load cached destinations off main actor to avoid UI freeze
    nonisolated private static func loadCachedDestinationsOffMainActor(from key: String) -> [DestinationType: [XcodeDestination]]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedDestinations.self, from: data) else {
            return nil
        }
        return cached.toDestinationDict()
    }

    nonisolated private static func loadLastDestinationId(from key: String) -> String {
        guard !key.isEmpty else { return "" }
        return UserDefaults.standard.string(forKey: key) ?? ""
    }

    nonisolated private func loadSavedScheme(for projectPath: String) -> String? {
        let key = Self.persistenceKey(prefix: "xcodeScheme", scopedTo: projectPath)
        return UserDefaults.standard.string(forKey: key)
    }

    func refreshDestinations() {
        Task { [weak self] in
            await self?.loadDestinations(force: true)
        }
    }

    // MARK: - Destination Caching

    private func cacheDestinations(_ destinations: [DestinationType: [XcodeDestination]]) {
        let allDestinations = destinations.flatMap { type, dests in
            dests.map { CachedDestination(destination: $0, type: type) }
        }
        let cached = CachedDestinations(destinations: allDestinations)

        guard !destinationsCacheKey.isEmpty else { return }

        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: destinationsCacheKey)
        }
    }

    private func loadDestinations(force: Bool = false) async {
        guard force || shouldRefreshDestinations(force: false) else { return }

        await MainActor.run {
            isLoadingDestinations = true
        }

        do {
            let destinations = try await deviceService.listDestinations()

            await MainActor.run {
                self.availableDestinations = destinations
                self.cacheDestinations(destinations)
                self.lastDestinationsRefreshAt = Date()

                // Restore last selected destination or pick first simulator
                let lastId = Self.loadLastDestinationId(from: self.lastDestinationIdKey)
                if !lastId.isEmpty,
                   let destination = self.findDestination(byId: lastId) {
                    self.selectedDestination = destination
                } else if self.selectedDestination == nil {
                    self.selectedDestination = destinations[.simulator]?.first { $0.platform == "iOS" }
                        ?? destinations[.mac]?.first
                }
            }

        } catch {
            logger.error("Failed to load destinations: \(error.localizedDescription)")
        }

        await MainActor.run {
            isLoadingDestinations = false
        }
    }

    private func shouldRefreshDestinations(force: Bool) -> Bool {
        guard !force else { return true }
        guard let lastRefreshAt = lastDestinationsRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefreshAt) >= destinationsRefreshTTL
    }

    private func findDestination(byId id: String) -> XcodeDestination? {
        for (_, destinations) in availableDestinations {
            if let destination = destinations.first(where: { $0.id == id }) {
                return destination
            }
        }
        return nil
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

    func findBuiltApp(project: XcodeProject, scheme: String) async throws -> String? {
        return try await findBuiltAppWithDestination(project: project, scheme: scheme, destination: nil)
    }

    func findBuiltAppForDevice(project: XcodeProject, scheme: String, destination: XcodeDestination) async throws -> String? {
        return try await findBuiltAppWithDestination(project: project, scheme: scheme, destination: destination)
    }

    private func findBuiltAppWithDestination(project: XcodeProject, scheme: String, destination: XcodeDestination?) async throws -> String? {
        // Get the build settings to find the built product path
        var arguments = ["-showBuildSettings", "-scheme", scheme]
        if project.isWorkspace {
            arguments.append(contentsOf: ["-workspace", project.path])
        } else {
            arguments.append(contentsOf: ["-project", project.path])
        }
        // Include destination to get correct build settings for device builds
        if let destination = destination {
            arguments.append(contentsOf: ["-destination", destination.destinationString])
        }

        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/xcodebuild",
            arguments: arguments
        )

        let output = result.stdout
        guard !output.isEmpty else { return nil }

        // Look for BUILT_PRODUCTS_DIR and FULL_PRODUCT_NAME
        var builtProductsDir: String?
        var productName: String?

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("BUILT_PRODUCTS_DIR = ") {
                builtProductsDir = String(trimmed.dropFirst("BUILT_PRODUCTS_DIR = ".count))
            } else if trimmed.hasPrefix("FULL_PRODUCT_NAME = ") {
                productName = String(trimmed.dropFirst("FULL_PRODUCT_NAME = ".count))
            }
        }

        guard let dir = builtProductsDir, let name = productName else { return nil }

        let appPath = (dir as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: appPath) {
            return appPath
        }

        return nil
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
