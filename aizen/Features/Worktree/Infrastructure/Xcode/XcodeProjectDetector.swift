//
//  XcodeProjectDetector.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeProjectDetector {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeProjectDetector")
    private let fileManager = FileManager.default

    // MARK: - Project Detection

    func detectProject(at path: String) async -> XcodeProject? {
        // Check for xcodebuild availability
        guard fileManager.fileExists(atPath: "/usr/bin/xcodebuild") else {
            logger.warning("xcodebuild not found - Xcode not installed")
            return nil
        }

        // Prefer .xcworkspace (handles CocoaPods, SPM)
        if let workspace = findWorkspace(at: path) {
            return await loadProject(path: workspace, isWorkspace: true)
        }

        // Fall back to .xcodeproj
        if let project = findProject(at: path) {
            return await loadProject(path: project, isWorkspace: false)
        }

        return nil
    }

    private func findWorkspace(at path: String) -> String? {
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") && !$0.contains("xcuserdata") }) {
                let fullPath = (path as NSString).appendingPathComponent(workspace)
                return fullPath
            }
        } catch {
            logger.error("Failed to list directory: \(error.localizedDescription)")
        }
        return nil
    }

    private func findProject(at path: String) -> String? {
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                let fullPath = (path as NSString).appendingPathComponent(project)
                return fullPath
            }
        } catch {
            logger.error("Failed to list directory: \(error.localizedDescription)")
        }
        return nil
    }

    private func loadProject(path: String, isWorkspace: Bool) async -> XcodeProject? {
        let name = (path as NSString).lastPathComponent

        do {
            let schemes = try await listSchemes(projectPath: path, isWorkspace: isWorkspace)
            guard !schemes.isEmpty else {
                logger.warning("No schemes found in project: \(path)")
                return nil
            }

            return XcodeProject(
                path: path,
                name: name,
                isWorkspace: isWorkspace,
                schemes: schemes
            )
        } catch {
            logger.error("Failed to load project: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Scheme Listing

    private func listSchemes(projectPath: String, isWorkspace: Bool) async throws -> [String] {
        var arguments = ["-list", "-json"]
        if isWorkspace {
            arguments.append(contentsOf: ["-workspace", projectPath])
        } else {
            arguments.append(contentsOf: ["-project", projectPath])
        }

        let environment = ShellEnvironment.loadUserShellEnvironment()

        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/xcodebuild",
            arguments: arguments,
            environment: environment
        )

        guard result.succeeded else {
            logger.error("xcodebuild -list failed: \(result.stderr)")
            throw XcodeError.commandFailed(result.stderr)
        }

        let data = result.stdout.data(using: .utf8) ?? Data()

        let decoder = JSONDecoder()
        let response = try decoder.decode(XcodeBuildListResponse.self, from: data)

        if let workspace = response.workspace {
            return workspace.schemes
        } else if let project = response.project {
            return project.schemes
        }

        return []
    }

    // MARK: - Bundle Identifier

    func getBundleIdentifier(project: XcodeProject, scheme: String) async throws -> String? {
        // Build settings contain PRODUCT_BUNDLE_IDENTIFIER
        var arguments = ["-showBuildSettings", "-scheme", scheme, "-json"]
        if project.isWorkspace {
            arguments.append(contentsOf: ["-workspace", project.path])
        } else {
            arguments.append(contentsOf: ["-project", project.path])
        }

        let environment = ShellEnvironment.loadUserShellEnvironment()

        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/xcodebuild",
            arguments: arguments,
            environment: environment
        )

        let output = result.stdout
        guard !output.isEmpty else { return nil }

        // Parse JSON output for PRODUCT_BUNDLE_IDENTIFIER
        // The output is an array of build settings objects
        if let jsonData = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            for targetSettings in json {
                if let buildSettings = targetSettings["buildSettings"] as? [String: Any],
                   let bundleId = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String {
                    return bundleId
                }
            }
        }

        // Fallback: grep for the identifier in non-JSON output
        for line in output.components(separatedBy: "\n") {
            if line.contains("PRODUCT_BUNDLE_IDENTIFIER") {
                let components = line.components(separatedBy: "=")
                if components.count >= 2 {
                    return components[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return nil
    }
}

// MARK: - Errors

enum XcodeError: Error, LocalizedError {
    case commandFailed(String)
    case projectNotFound
    case noSchemesFound
    case buildFailed(String)
    case launchFailed(String)
    case installFailed(String)
    case xcodeNotInstalled

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .projectNotFound:
            return "No Xcode project found"
        case .noSchemesFound:
            return "No schemes found in project"
        case .buildFailed(let message):
            return "Build failed: \(message)"
        case .launchFailed(let message):
            return "Launch failed: \(message)"
        case .installFailed(let message):
            return "Install failed: \(message)"
        case .xcodeNotInstalled:
            return "Xcode is not installed"
        }
    }
}
