//
//  XcodeDeviceService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeDeviceService {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeDeviceService")

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
