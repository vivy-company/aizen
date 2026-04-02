//
//  XcodeDeviceService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeDeviceService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeDeviceService")

    // MARK: - List Destinations

    func listDestinations() async throws -> [DestinationType: [XcodeDestination]] {
        var destinations: [DestinationType: [XcodeDestination]] = [:]

        // Get simulators
        let simulators = try await listSimulators()
        if !simulators.isEmpty {
            destinations[.simulator] = simulators
        }

        // Get physical devices
        let devices = try await listPhysicalDevices()
        if !devices.isEmpty {
            destinations[.device] = devices
        }

        // Add My Mac
        destinations[.mac] = [await createMacDestination()]

        return destinations
    }

    // MARK: - Simulators

    private func listSimulators() async throws -> [XcodeDestination] {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "--json"]
        )

        guard result.succeeded else {
            logger.error("simctl list devices failed")
            return []
        }

        let data = result.stdout.data(using: .utf8) ?? Data()

        let decoder = JSONDecoder()
        let response = try decoder.decode(SimctlDevicesResponse.self, from: data)

        var destinations: [XcodeDestination] = []

        for (runtime, devices) in response.devices {
            // Parse runtime: com.apple.CoreSimulator.SimRuntime.iOS-17-0
            let runtimeComponents = runtime.components(separatedBy: ".")
            guard let lastComponent = runtimeComponents.last else { continue }

            // Parse platform and version: iOS-17-0 -> iOS, 17.0
            let platformVersion = lastComponent.components(separatedBy: "-")
            guard platformVersion.count >= 2 else { continue }

            let platform = platformVersion[0]
            let version = platformVersion.dropFirst().joined(separator: ".")

            // Filter to iOS and common platforms
            guard ["iOS", "watchOS", "tvOS", "visionOS"].contains(platform) else { continue }

            for device in devices {
                // Skip unavailable simulators
                guard device.isAvailable else { continue }

                let destination = XcodeDestination(
                    id: device.udid,
                    name: device.name,
                    type: .simulator,
                    platform: platform,
                    osVersion: version,
                    isAvailable: device.isAvailable
                )
                destinations.append(destination)
            }
        }

        // Sort by platform, then by version (newest first), then by name
        destinations.sort { lhs, rhs in
            if lhs.platform != rhs.platform {
                // iOS first
                if lhs.platform == "iOS" { return true }
                if rhs.platform == "iOS" { return false }
                return lhs.platform < rhs.platform
            }
            if lhs.osVersion != rhs.osVersion {
                return (lhs.osVersion ?? "") > (rhs.osVersion ?? "")
            }
            return lhs.name < rhs.name
        }

        return destinations
    }

    // MARK: - Physical Devices

    private func listPhysicalDevices() async throws -> [XcodeDestination] {
        // Use devicectl to get devices with CoreDevice UUIDs (required for xcodebuild)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("devicectl_\(UUID().uuidString).json")

        let exitCode = try await ProcessExecutor.shared.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", tempFile.path]
        )

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        guard exitCode == 0,
              let jsonData = try? Data(contentsOf: tempFile) else {
            logger.warning("Failed to list devices via devicectl")
            return []
        }

        let response = try JSONDecoder().decode(DeviceCtlResponse.self, from: jsonData)

        var destinations: [XcodeDestination] = []

        for device in response.result.devices {
            // Skip Macs (we add separately), watches, and unavailable devices
            let deviceType = device.hardwareProperties.deviceType.lowercased()
            guard deviceType == "iphone" || deviceType == "ipad" else { continue }

            // Check if device is available
            let isPaired = device.connectionProperties?.pairingState == "paired"
            guard isPaired else { continue }

            // Use UDID for xcodebuild (not CoreDevice identifier)
            guard let udid = device.hardwareProperties.udid else { continue }

            let destination = XcodeDestination(
                id: udid,
                name: device.deviceProperties.name,
                type: .device,
                platform: device.hardwareProperties.platform,
                osVersion: device.deviceProperties.osVersionNumber,
                isAvailable: isPaired
            )
            destinations.append(destination)
        }

        // Sort by name
        destinations.sort { $0.name < $1.name }

        return destinations
    }

    private func createMacDestination() async -> XcodeDestination {
        var macName = "My Mac"

        // Get Mac model name
        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/sbin/system_profiler",
                arguments: ["SPHardwareDataType", "-detailLevel", "mini"]
            )

            if result.succeeded {
                for line in result.stdout.components(separatedBy: "\n") {
                    if line.contains("Model Name:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count >= 2 {
                            macName = parts[1].trimmingCharacters(in: .whitespaces)
                        }
                        break
                    }
                }
            }
        } catch {
            logger.warning("Failed to get Mac model name")
        }

        return XcodeDestination(
            id: "macos",
            name: macName,
            type: .mac,
            platform: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            isAvailable: true
        )
    }

    // MARK: - Simulator Control

    func bootSimulatorIfNeeded(id: String) async throws {
        let exitCode = try await ProcessExecutor.shared.execute(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "boot", id]
        )

        // Exit code 149 means already booted, which is fine
        if exitCode != 0 && exitCode != 149 {
            logger.warning("Failed to boot simulator \(id), exit code: \(exitCode)")
        }
    }

    func launchInSimulator(deviceId: String, bundleId: String) async throws {
        // First boot the simulator
        try await bootSimulatorIfNeeded(id: deviceId)

        // Small delay to ensure simulator is ready
        try await Task.sleep(nanoseconds: 500_000_000)

        // Launch the app
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "launch", deviceId, bundleId]
        )

        if !result.succeeded {
            throw XcodeError.launchFailed(result.stderr.isEmpty ? "Unknown error" : result.stderr)
        }
    }

    func openSimulatorApp() async {
        _ = try? await ProcessExecutor.shared.execute(
            executable: "/usr/bin/open",
            arguments: ["-a", "Simulator"]
        )
    }

    // MARK: - App Termination

    func terminateInSimulator(deviceId: String, bundleId: String) async {
        do {
            _ = try await ProcessExecutor.shared.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "terminate", deviceId, bundleId]
            )
            logger.debug("Terminated \(bundleId) on simulator \(deviceId)")
        } catch {
            logger.debug("Failed to terminate app (may not be running): \(error.localizedDescription)")
        }
    }

    func terminateMacApp(bundleId: String) async {
        // Use osascript to quit the app gracefully by bundle ID
        do {
            _ = try await ProcessExecutor.shared.execute(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application id \"\(bundleId)\" to quit"]
            )
            // Give the app a moment to quit gracefully
            try? await Task.sleep(nanoseconds: 500_000_000)
            logger.debug("Terminated Mac app with bundle ID \(bundleId)")
        } catch {
            logger.debug("Failed to terminate Mac app (may not be running): \(error.localizedDescription)")
        }
    }

    func terminateMacAppByPath(_ appPath: String) async {
        // Extract app name from path and use killall
        let appName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        do {
            _ = try await ProcessExecutor.shared.execute(
                executable: "/usr/bin/killall",
                arguments: [appName]
            )
            logger.debug("Terminated Mac app: \(appName)")
        } catch {
            logger.debug("Failed to terminate Mac app (may not be running): \(error.localizedDescription)")
        }
    }

    // MARK: - Physical Device Control

    func installOnDevice(deviceId: String, appPath: String) async throws {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/xcrun",
            arguments: ["devicectl", "device", "install", "app", "--device", deviceId, appPath]
        )

        if !result.succeeded {
            let errorMessage = result.stderr.isEmpty ? "Unknown error" : result.stderr
            logger.error("Failed to install app on device: \(errorMessage)")
            throw XcodeError.installFailed(errorMessage)
        }

        logger.info("Installed \(appPath) on device \(deviceId)")
    }

    func terminateOnDevice(deviceId: String, bundleId: String) async {
        do {
            _ = try await ProcessExecutor.shared.execute(
                executable: "/usr/bin/xcrun",
                arguments: ["devicectl", "device", "process", "terminate", "--device", deviceId, bundleId]
            )
            logger.debug("Terminated \(bundleId) on device \(deviceId)")
        } catch {
            logger.debug("Failed to terminate app on device (may not be running): \(error.localizedDescription)")
        }
    }

    /// Launch app on physical device with console output capture
    /// Returns the process that's streaming console output (caller must handle pipes)
    func launchOnDeviceWithConsole(deviceId: String, bundleId: String) async throws -> Process {
        // First terminate any existing instance
        await terminateOnDevice(deviceId: deviceId, bundleId: bundleId)
        try await Task.sleep(nanoseconds: 300_000_000)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "devicectl", "device", "process", "launch",
            "--device", deviceId,
            "--terminate-existing",
            "--console",
            bundleId
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        logger.info("Launched \(bundleId) on device \(deviceId) with console")

        return process
    }
}
