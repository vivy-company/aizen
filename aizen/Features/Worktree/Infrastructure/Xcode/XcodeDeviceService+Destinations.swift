//
//  XcodeDeviceService+Destinations.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os

extension XcodeDeviceService {
    func listDestinations() async throws -> [DestinationType: [XcodeDestination]] {
        var destinations: [DestinationType: [XcodeDestination]] = [:]

        let simulators = try await listSimulators()
        if !simulators.isEmpty {
            destinations[.simulator] = simulators
        }

        let devices = try await listPhysicalDevices()
        if !devices.isEmpty {
            destinations[.device] = devices
        }

        destinations[.mac] = [await createMacDestination()]
        return destinations
    }

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
        let response = try JSONDecoder().decode(SimctlDevicesResponse.self, from: data)

        var destinations: [XcodeDestination] = []

        for (runtime, devices) in response.devices {
            let runtimeComponents = runtime.components(separatedBy: ".")
            guard let lastComponent = runtimeComponents.last else { continue }

            let platformVersion = lastComponent.components(separatedBy: "-")
            guard platformVersion.count >= 2 else { continue }

            let platform = platformVersion[0]
            let version = platformVersion.dropFirst().joined(separator: ".")

            guard ["iOS", "watchOS", "tvOS", "visionOS"].contains(platform) else { continue }

            for device in devices where device.isAvailable {
                destinations.append(
                    XcodeDestination(
                        id: device.udid,
                        name: device.name,
                        type: .simulator,
                        platform: platform,
                        osVersion: version,
                        isAvailable: device.isAvailable
                    )
                )
            }
        }

        destinations.sort { lhs, rhs in
            if lhs.platform != rhs.platform {
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

    private func listPhysicalDevices() async throws -> [XcodeDestination] {
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
            let deviceType = device.hardwareProperties.deviceType.lowercased()
            guard deviceType == "iphone" || deviceType == "ipad" else { continue }

            let isPaired = device.connectionProperties?.pairingState == "paired"
            guard isPaired else { continue }

            guard let udid = device.hardwareProperties.udid else { continue }

            destinations.append(
                XcodeDestination(
                    id: udid,
                    name: device.deviceProperties.name,
                    type: .device,
                    platform: device.hardwareProperties.platform,
                    osVersion: device.deviceProperties.osVersionNumber,
                    isAvailable: isPaired
                )
            )
        }

        destinations.sort { $0.name < $1.name }
        return destinations
    }

    private func createMacDestination() async -> XcodeDestination {
        var macName = "My Mac"

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
}
