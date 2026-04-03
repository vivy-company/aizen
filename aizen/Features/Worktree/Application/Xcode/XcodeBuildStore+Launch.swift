//
//  XcodeBuildStore+Launch.swift
//  aizen
//
//  Launch and launched-process lifecycle support for Xcode builds
//

import Foundation
import os

extension XcodeBuildStore {
    func launchInSimulator(project: XcodeProject, scheme: String, destination: XcodeDestination) async {
        await MainActor.run {
            currentPhase = .launching
        }

        await deviceService.openSimulatorApp()

        do {
            let bundleId = try await projectDetector.getBundleIdentifier(project: project, scheme: scheme)

            guard let bundleId else {
                logger.warning("Could not determine bundle identifier for launch")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            await deviceService.terminateInSimulator(deviceId: destination.id, bundleId: bundleId)
            try await deviceService.launchInSimulator(deviceId: destination.id, bundleId: bundleId)

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

    func launchOnMac(project: XcodeProject, scheme: String) async {
        await MainActor.run {
            currentPhase = .launching
        }

        do {
            let appPath = try await findBuiltApp(project: project, scheme: scheme)

            guard let appPath else {
                logger.warning("Could not find built app")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            let bundleId = try await projectDetector.getBundleIdentifier(project: project, scheme: scheme)
            await terminatePreviousLaunch()

            let executablePath = (appPath as NSString).appendingPathComponent(
                "Contents/MacOS/\((appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""))"
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = []

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var env = ProcessInfo.processInfo.environment
            env["NSUnbufferedIO"] = "YES"
            process.environment = env

            try process.run()

            let pid = process.processIdentifier

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

            startAppMonitoring()
        } catch {
            logger.error("Failed to launch on Mac: \(error.localizedDescription)")
            await MainActor.run {
                currentPhase = .failed(error: "Launch failed: \(error.localizedDescription)", log: "")
            }
        }
    }

    func launchOnDevice(project: XcodeProject, scheme: String, destination: XcodeDestination) async {
        await MainActor.run {
            currentPhase = .launching
        }

        do {
            let bundleId = try await projectDetector.getBundleIdentifier(project: project, scheme: scheme)

            guard let bundleId else {
                logger.warning("Could not determine bundle identifier for device launch")
                await MainActor.run {
                    currentPhase = .succeeded
                }
                return
            }

            let appPath = try await findBuiltAppForDevice(project: project, scheme: scheme, destination: destination)
            if let appPath {
                try await deviceService.installOnDevice(deviceId: destination.id, appPath: appPath)
            }

            let process = try await deviceService.launchOnDeviceWithConsole(deviceId: destination.id, bundleId: bundleId)
            let outputPipe = process.standardOutput as? Pipe
            let errorPipe = process.standardError as? Pipe

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

            startAppMonitoring()
        } catch {
            logger.error("Failed to launch on device: \(error.localizedDescription)")
            await MainActor.run {
                currentPhase = .failed(error: "Launch failed: \(error.localizedDescription)", log: "")
            }
        }
    }

    func terminatePreviousLaunch() async {
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

    func startAppMonitoring() {
        appMonitorTask?.cancel()

        appMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                guard let self else { break }

                let pid = await MainActor.run { self.launchedPID }
                guard let pid else { break }

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

    func clearLaunchState() {
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

    func closeLaunchPipes() {
        if let outputPipe = launchedOutputPipe {
            try? outputPipe.fileHandleForReading.close()
        }
        if let errorPipe = launchedErrorPipe {
            try? errorPipe.fileHandleForReading.close()
        }
        launchedOutputPipe = nil
        launchedErrorPipe = nil
    }
}
