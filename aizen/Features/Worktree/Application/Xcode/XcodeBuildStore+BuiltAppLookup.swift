//
//  XcodeBuildStore+BuiltAppLookup.swift
//  aizen
//
//  Built app discovery helpers for launch and install flows
//

import Foundation

extension XcodeBuildStore {
    func findBuiltApp(project: XcodeProject, scheme: String) async throws -> String? {
        try await findBuiltAppWithDestination(project: project, scheme: scheme, destination: nil)
    }

    func findBuiltAppForDevice(project: XcodeProject, scheme: String, destination: XcodeDestination) async throws -> String? {
        try await findBuiltAppWithDestination(project: project, scheme: scheme, destination: destination)
    }

    func findBuiltAppWithDestination(project: XcodeProject, scheme: String, destination: XcodeDestination?) async throws -> String? {
        var arguments = ["-showBuildSettings", "-scheme", scheme]
        if project.isWorkspace {
            arguments.append(contentsOf: ["-workspace", project.path])
        } else {
            arguments.append(contentsOf: ["-project", project.path])
        }
        if let destination {
            arguments.append(contentsOf: ["-destination", destination.destinationString])
        }

        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/xcodebuild",
            arguments: arguments
        )

        let output = result.stdout
        guard !output.isEmpty else { return nil }

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
}
