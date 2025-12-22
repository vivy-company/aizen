//
//  XcodeBuildManager.swift
//  aizen
//
//  Xcode build and run management
//

import Foundation
import SwiftUI
import Combine
import os.log

class XcodeBuildManager: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeBuildManager")

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

    private var appMonitorTask: Task<Void, Never>?

    // MARK: - Persistence

    private var lastDestinationId: String {
        get { UserDefaults.standard.string(forKey: "xcodeLastDestinationId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "xcodeLastDestinationId") }
    }

    private var projectSchemeKey: String {
        guard let project = detectedProject else { return "" }
        return "xcodeScheme_\(project.path.hashValue)"
    }

    // MARK: - Services

    private let projectDetector = XcodeProjectDetector()
    private let deviceService = XcodeDeviceService()
    private let buildService = XcodeBuildService()

    private var buildTask: Task<Void, Never>?
    private var currentWorktreePath: String?

    init() {}

    // MARK: - Detection

    func detectProject(at path: String) {
        guard path != currentWorktreePath else { return }
        currentWorktreePath = path

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Reset state on main actor to ensure proper UI updates
            self.detectedProject = nil
            self.selectedScheme = nil
            self.currentPhase = .idle
            self.lastBuildLog = nil
            self.isReady = false

            // Detect project (runs off main actor)
            let project = await self.projectDetector.detectProject(at: path)

            guard let project = project else {
                return  // isReady stays false
            }

            // Load cached destinations immediately (non-blocking)
            self.loadCachedDestinations()

            // Set project and scheme
            self.detectedProject = project

            // Restore or auto-select scheme
            let savedScheme = UserDefaults.standard.string(forKey: self.projectSchemeKey)
            if let saved = savedScheme, project.schemes.contains(saved) {
                self.selectedScheme = saved
            } else {
                self.selectedScheme = project.schemes.first
            }

            // Mark as ready immediately if we have cached destinations
            if !self.availableDestinations.isEmpty {
                self.isReady = true
                // Refresh destinations in background
                Task {
                    await self.loadDestinations(force: false)
                }
            } else {
                // First time: must wait for destinations
                await self.loadDestinations(force: true)
                self.isReady = true
            }
        }
    }

    func refreshDestinations() {
        Task { [weak self] in
            await self?.loadDestinations(force: true)
        }
    }

    // MARK: - Destination Caching

    private let destinationsCacheKey = "xcodeDestinationsCache"

    private func loadCachedDestinations() {
        guard let data = UserDefaults.standard.data(forKey: destinationsCacheKey),
              let cached = try? JSONDecoder().decode(CachedDestinations.self, from: data) else {
            return
        }

        self.availableDestinations = cached.toDestinationDict()

        // Restore selected destination
        if let lastId = lastDestinationId.isEmpty ? nil : lastDestinationId,
           let destination = findDestination(byId: lastId) {
            self.selectedDestination = destination
        } else if selectedDestination == nil {
            self.selectedDestination = availableDestinations[.simulator]?.first { $0.platform == "iOS" }
                ?? availableDestinations[.mac]?.first
        }
    }

    private func cacheDestinations(_ destinations: [DestinationType: [XcodeDestination]]) {
        let allDestinations = destinations.flatMap { type, dests in
            dests.map { CachedDestination(destination: $0, type: type) }
        }
        let cached = CachedDestinations(destinations: allDestinations)

        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: destinationsCacheKey)
        }
    }

    private func loadDestinations(force: Bool = false) async {
        await MainActor.run {
            isLoadingDestinations = true
        }

        do {
            let destinations = try await deviceService.listDestinations()

            await MainActor.run {
                self.availableDestinations = destinations
                self.cacheDestinations(destinations)

                // Restore last selected destination or pick first simulator
                if let lastId = self.lastDestinationId.isEmpty ? nil : self.lastDestinationId,
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
        UserDefaults.standard.set(scheme, forKey: projectSchemeKey)
    }

    // MARK: - Destination Selection

    func selectDestination(_ destination: XcodeDestination) {
        selectedDestination = destination
        lastDestinationId = destination.id
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

        buildTask = Task { [weak self] in
            guard let self = self else { return }

            for await phase in await self.buildService.buildAndRun(
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

    private func launchInSimulator(project: XcodeProject, scheme: String, destination: XcodeDestination) async {
        await MainActor.run {
            currentPhase = .launching
        }

        // Open Simulator app
        await deviceService.openSimulatorApp()

        do {
            // Get bundle identifier
            let bundleId = try await projectDetector.getBundleIdentifier(project: project, scheme: scheme)

            guard let bundleId = bundleId else {
                logger.warning("Could not determine bundle identifier for launch")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            // Terminate previous instance before launching new one
            await deviceService.terminateInSimulator(deviceId: destination.id, bundleId: bundleId)

            // Launch the app
            try await deviceService.launchInSimulator(deviceId: destination.id, bundleId: bundleId)

            // Store launch info for future termination and log streaming
            await MainActor.run {
                self.launchedBundleId = bundleId
                self.launchedDestination = destination
                self.launchedAppPath = nil
                currentPhase = .succeeded
            }
        } catch {
            logger.error("Failed to launch in simulator: \(error.localizedDescription)")
            await MainActor.run {
                currentPhase = .failed(error: "Launch failed: \(error.localizedDescription)", log: "")
            }
        }
    }

    private func launchOnMac(project: XcodeProject, scheme: String) async {
        await MainActor.run {
            currentPhase = .launching
        }

        do {
            // Find the built app in DerivedData
            let appPath = try await findBuiltApp(project: project, scheme: scheme)

            guard let appPath = appPath else {
                logger.warning("Could not find built app")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            // Get bundle identifier for the app
            let bundleId = try await projectDetector.getBundleIdentifier(project: project, scheme: scheme)

            // Terminate previous instance we launched (by PID if available)
            await terminatePreviousLaunch()

            // Launch the app directly (not via 'open') to capture stdout/stderr
            let executablePath = (appPath as NSString).appendingPathComponent("Contents/MacOS/\((appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""))")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = []

            // Set up pipes to capture stdout/stderr
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Set environment for proper app behavior
            var env = ProcessInfo.processInfo.environment
            env["NSUnbufferedIO"] = "YES"  // Disable output buffering
            process.environment = env

            try process.run()

            let pid = process.processIdentifier

            // Store launch info for future termination and log streaming
            await MainActor.run {
                self.launchedBundleId = bundleId
                self.launchedDestination = selectedDestination
                self.launchedAppPath = appPath
                self.launchedPID = pid
                self.launchedProcess = process
                self.launchedOutputPipe = outputPipe
                self.launchedErrorPipe = errorPipe
                currentPhase = .succeeded
            }

            // Start monitoring if the app is still running
            startAppMonitoring()

        } catch {
            logger.error("Failed to launch on Mac: \(error.localizedDescription)")
            await MainActor.run {
                currentPhase = .failed(error: "Launch failed: \(error.localizedDescription)", log: "")
            }
        }
    }

    private func launchOnDevice(project: XcodeProject, scheme: String, destination: XcodeDestination) async {
        await MainActor.run {
            currentPhase = .launching
        }

        do {
            // Get bundle identifier
            let bundleId = try await projectDetector.getBundleIdentifier(project: project, scheme: scheme)

            guard let bundleId = bundleId else {
                logger.warning("Could not determine bundle identifier for device launch")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            // Find the built app and install it on device
            let appPath = try await findBuiltAppForDevice(project: project, scheme: scheme, destination: destination)
            if let appPath = appPath {
                try await deviceService.installOnDevice(deviceId: destination.id, appPath: appPath)
            }

            // Launch app on device with console capture using devicectl
            let process = try await deviceService.launchOnDeviceWithConsole(deviceId: destination.id, bundleId: bundleId)

            // Get the pipes from the process
            let outputPipe = process.standardOutput as? Pipe
            let errorPipe = process.standardError as? Pipe

            // Store launch info for future termination and log streaming
            await MainActor.run {
                self.launchedBundleId = bundleId
                self.launchedDestination = destination
                self.launchedAppPath = nil
                self.launchedPID = process.processIdentifier
                self.launchedProcess = process
                self.launchedOutputPipe = outputPipe
                self.launchedErrorPipe = errorPipe
                currentPhase = .succeeded
            }

            // Start monitoring if the devicectl process is still running
            startAppMonitoring()

        } catch {
            logger.error("Failed to launch on device: \(error.localizedDescription)")
            await MainActor.run {
                currentPhase = .failed(error: "Launch failed: \(error.localizedDescription)", log: "")
            }
        }
    }

    private func terminatePreviousLaunch() async {
        // If we have a process reference, terminate it directly
        if let process = await MainActor.run(body: { self.launchedProcess }) {
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            await MainActor.run {
                self.closeLaunchPipes()
            }
            return
        }

        // Fallback: terminate by PID if we don't have process reference
        if let pid = await MainActor.run(body: { self.launchedPID }) {
            _ = try? await ProcessExecutor.shared.execute(
                executable: "/bin/kill",
                arguments: [String(pid)]
            )
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                self.closeLaunchPipes()
            }
        }
    }

    private func getPIDForApp(appPath: String) async -> Int32? {
        let appName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        guard let result = try? await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/pgrep",
            arguments: ["-n", appName]
        ) else {
            return nil
        }

        return Int32(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func startAppMonitoring() {
        // Cancel any existing monitor
        appMonitorTask?.cancel()

        appMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Check every 2 seconds

                guard let self = self else { break }

                let pid = await MainActor.run { self.launchedPID }
                guard let pid = pid else { break }

                // Check if process is still running
                let isRunning = kill(pid, 0) == 0

                if !isRunning {
                    await MainActor.run {
                        self.clearLaunchState()
                    }
                    break
                }
            }
        }
    }

    private func clearLaunchState() {
        stopLogStream()
        launchedBundleId = nil
        launchedDestination = nil
        launchedAppPath = nil
        launchedPID = nil
        launchedProcess = nil
        closeLaunchPipes()
        appMonitorTask?.cancel()
        appMonitorTask = nil
    }

    private func closeLaunchPipes() {
        if let outputPipe = launchedOutputPipe {
            try? outputPipe.fileHandleForReading.close()
        }
        if let errorPipe = launchedErrorPipe {
            try? errorPipe.fileHandleForReading.close()
        }
        launchedOutputPipe = nil
        launchedErrorPipe = nil
    }

    private func findBuiltApp(project: XcodeProject, scheme: String) async throws -> String? {
        return try await findBuiltAppWithDestination(project: project, scheme: scheme, destination: nil)
    }

    private func findBuiltAppForDevice(project: XcodeProject, scheme: String, destination: XcodeDestination) async throws -> String? {
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

    private let logService = XcodeLogService()
    private var logStreamTask: Task<Void, Never>?

    private var macLogStreamTask: Task<Void, Never>?

    func startLogStream() {
        guard let bundleId = launchedBundleId,
              let destination = launchedDestination else {
            logger.warning("Cannot start log stream: no launched app info")
            return
        }

        // Stop any existing stream
        stopLogStream()

        isLogStreamActive = true
        logOutput = []

        let appName = (self.launchedAppPath as NSString?)?.lastPathComponent ?? bundleId

        // For Mac apps: run BOTH pipe streaming (for print()) AND os_log streaming (for Logger)
        if destination.type == .mac,
           let outputPipe = self.launchedOutputPipe,
           let errorPipe = self.launchedErrorPipe {

            // Start pipe streaming for stdout/stderr (captures print())
            logStreamTask = Task { [weak self] in
                guard let self = self else { return }

                let pipeStream = await self.logService.startStreamingFromPipes(
                    outputPipe: outputPipe,
                    errorPipe: errorPipe,
                    appName: appName
                )

                for await line in pipeStream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }
            }

            // Start os_log streaming (captures Logger/os.log)
            macLogStreamTask = Task { [weak self] in
                guard let self = self else { return }

                let osLogStream = await self.logService.startStreamingForMacApp(
                    bundleId: bundleId,
                    processName: appName
                )

                for await line in osLogStream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }

                await MainActor.run {
                    self.isLogStreamActive = false
                }
            }
        } else if destination.type == .device,
                  let outputPipe = self.launchedOutputPipe,
                  let errorPipe = self.launchedErrorPipe {
            // For physical devices, use pipe streaming only (device logs require different tools)
            logStreamTask = Task { [weak self] in
                guard let self = self else { return }

                let stream = await self.logService.startStreamingFromPipes(
                    outputPipe: outputPipe,
                    errorPipe: errorPipe,
                    appName: appName
                )

                for await line in stream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }

                await MainActor.run {
                    self.isLogStreamActive = false
                }
            }
        } else {
            // For simulators, use log stream command (already captures both)
            logStreamTask = Task { [weak self] in
                guard let self = self else { return }

                let stream = await self.logService.startStreaming(bundleId: bundleId, destination: destination)

                for await line in stream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }

                await MainActor.run {
                    self.isLogStreamActive = false
                }
            }
        }
    }

    private func appendLogLine(_ line: String) {
        logOutput.append(line)
        // Limit log buffer to prevent memory issues
        if logOutput.count > 10000 {
            logOutput.removeFirst(1000)
        }
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        macLogStreamTask?.cancel()
        macLogStreamTask = nil
        Task {
            await logService.stopAllStreaming()
        }
        isLogStreamActive = false
    }

    func clearLogs() {
        logOutput = []
    }
}
