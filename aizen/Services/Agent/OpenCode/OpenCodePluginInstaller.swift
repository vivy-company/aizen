//
//  OpenCodePluginInstaller.swift
//  aizen
//
//  Handles global npm installation for OpenCode plugins (oh-my-opencode, auth plugins, etc.)
//  Unlike regular agent plugins, OpenCode plugins are installed globally with `npm install -g`
//

import Foundation
import os.log

enum OpenCodePluginError: Error, LocalizedError {
    case npmNotFound
    case installFailed(String)
    case uninstallFailed(String)
    case versionCheckFailed
    
    var errorDescription: String? {
        switch self {
        case .npmNotFound:
            return "npm not found. Please install Node.js and npm."
        case .installFailed(let detail):
            return "Plugin installation failed: \(detail)"
        case .uninstallFailed(let detail):
            return "Plugin uninstallation failed: \(detail)"
        case .versionCheckFailed:
            return "Failed to check plugin version"
        }
    }
}

struct OpenCodePluginInfo {
    let name: String
    let displayName: String
    let description: String
    let npmPackage: String
    let isInstalled: Bool
    let installedVersion: String?
    let latestVersion: String?
    let isRegistered: Bool
    
    var needsUpdate: Bool {
        guard let installed = installedVersion, let latest = latestVersion else { return false }
        return installed != latest
    }
}

actor OpenCodePluginInstaller {
    static let shared = OpenCodePluginInstaller()
    
    private let configService: OpenCodeConfigService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "OpenCodePluginInstaller")
    
    static let knownPlugins: [(name: String, displayName: String, description: String, npmPackage: String)] = [
        ("oh-my-opencode", "Oh My OpenCode", "Plugin system with custom agents, hooks, and MCP servers", "oh-my-opencode"),
        ("opencode-openai-codex-auth", "OpenAI Codex Auth", "Authentication for OpenAI Codex models", "opencode-openai-codex-auth"),
        ("opencode-gemini-auth", "Gemini Auth", "Authentication for Google Gemini models", "opencode-gemini-auth"),
        ("opencode-antigravity-auth", "Antigravity Auth", "OAuth authentication for Antigravity models", "opencode-antigravity-auth")
    ]
    
    init(configService: OpenCodeConfigService = .shared) {
        self.configService = configService
    }
    
    private func validatePackageName(_ name: String) throws {
        let pattern = "^(@[a-z0-9-]+/)?[a-z0-9-]+$"
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw OpenCodePluginError.installFailed("Invalid package name: \(name)")
        }
        
        guard Self.knownPlugins.contains(where: { $0.npmPackage == name }) else {
            throw OpenCodePluginError.installFailed("Unknown plugin: \(name)")
        }
    }
    
    func checkNpmAvailable() async -> Bool {
        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()
        let result = try? await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/env",
            arguments: ["npm", "--version"],
            environment: shellEnv
        )
        return result?.succeeded ?? false
    }
    
    func isInstalled(_ packageName: String) async -> Bool {
        if getVersionFromPackageJson(packageName) != nil {
            return true
        }
        
        if checkCommonBinaryLocations(packageName) {
            return true
        }
        
        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()
        
        let whichResult = try? await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/env",
            arguments: ["which", packageName],
            environment: shellEnv
        )
        if whichResult?.succeeded == true {
            return true
        }
        
        let npmResult = try? await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/env",
            arguments: ["npm", "list", "-g", packageName, "--depth=0", "--json"],
            environment: shellEnv
        )
        
        if let npmResult = npmResult, npmResult.succeeded,
           let data = npmResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let deps = json["dependencies"] as? [String: Any],
           deps[packageName] != nil {
            return true
        }
        
        return false
    }
    
    private func checkCommonBinaryLocations(_ packageName: String) -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        
        let binaryPaths = [
            "\(home)/.volta/bin/\(packageName)",
            "\(home)/.nvm/versions/node/current/bin/\(packageName)",
            "\(home)/.fnm/aliases/default/bin/\(packageName)",
            "\(home)/.asdf/shims/\(packageName)",
            "\(home)/.local/share/pnpm/\(packageName)",
            "\(home)/.bun/bin/\(packageName)",
            "/usr/local/bin/\(packageName)",
            "/opt/homebrew/bin/\(packageName)"
        ]
        
        for path in binaryPaths {
            if fm.fileExists(atPath: path) {
                return true
            }
        }
        
        if let nvmPath = findInNVMVersions(packageName, home: home) {
            return fm.fileExists(atPath: nvmPath)
        }
        
        if let fnmPath = findInFNMVersions(packageName, home: home) {
            return fm.fileExists(atPath: fnmPath)
        }
        
        if let asdfPath = findInAsdfVersions(packageName, home: home) {
            return fm.fileExists(atPath: asdfPath)
        }
        
        return false
    }
    
    private func findInNVMVersions(_ packageName: String, home: String) -> String? {
        let nvmVersionsPath = "\(home)/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsPath) else {
            return nil
        }
        
        for version in versions.sorted().reversed() {
            let binPath = "\(nvmVersionsPath)/\(version)/bin/\(packageName)"
            if FileManager.default.fileExists(atPath: binPath) {
                return binPath
            }
        }
        return nil
    }
    
    private func findInFNMVersions(_ packageName: String, home: String) -> String? {
        let fnmVersionsPath = "\(home)/.fnm/node-versions"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: fnmVersionsPath) else {
            return nil
        }
        
        for version in versions.sorted().reversed() {
            let binPath = "\(fnmVersionsPath)/\(version)/installation/bin/\(packageName)"
            if FileManager.default.fileExists(atPath: binPath) {
                return binPath
            }
        }
        return nil
    }
    
    private func findInAsdfVersions(_ packageName: String, home: String) -> String? {
        let asdfNodePath = "\(home)/.asdf/installs/nodejs"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: asdfNodePath) else {
            return nil
        }
        
        for version in versions.sorted().reversed() {
            let binPath = "\(asdfNodePath)/\(version)/bin/\(packageName)"
            if FileManager.default.fileExists(atPath: binPath) {
                return binPath
            }
        }
        return nil
    }
    
    func getInstalledVersion(_ packageName: String) async -> String? {
        if let version = getVersionFromPackageJson(packageName) {
            return version
        }
        
        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()
        
        let voltaListResult = try? await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/env",
            arguments: ["volta", "list", "--format=plain"],
            environment: shellEnv
        )
        
        if let voltaListResult = voltaListResult, voltaListResult.succeeded {
            for line in voltaListResult.stdout.components(separatedBy: "\n") {
                if line.contains("package \(packageName)@") {
                    if let atRange = line.range(of: "\(packageName)@"),
                       let spaceRange = line[atRange.upperBound...].firstIndex(of: " ") {
                        return String(line[atRange.upperBound..<spaceRange])
                    }
                }
            }
        }
        
        let npmResult = try? await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/env",
            arguments: ["npm", "list", "-g", packageName, "--depth=0", "--json"],
            environment: shellEnv
        )
        
        if let npmResult = npmResult, npmResult.succeeded,
           let data = npmResult.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let deps = json["dependencies"] as? [String: Any],
           let pkg = deps[packageName] as? [String: Any],
           let version = pkg["version"] as? String {
            return version
        }
        
        return nil
    }
    
    private func getVersionFromPackageJson(_ packageName: String) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        
        let packageJsonPaths = [
            findPackageJsonInNVM(packageName, home: home),
            findPackageJsonInFNM(packageName, home: home),
            findPackageJsonInAsdf(packageName, home: home),
            findPackageJsonInVolta(packageName, home: home),
            findPackageJsonInPnpm(packageName, home: home),
            findPackageJsonInBun(packageName, home: home)
        ].compactMap { $0 }
        
        for packageJsonPath in packageJsonPaths {
            if let version = parseVersionFromPackageJson(packageJsonPath) {
                return version
            }
        }
        
        return nil
    }
    
    private func parseVersionFromPackageJson(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            return nil
        }
        return version
    }
    
    private func findPackageJsonInNVM(_ packageName: String, home: String) -> String? {
        let nvmVersionsPath = "\(home)/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsPath) else {
            return nil
        }
        
        for version in versions.sorted().reversed() {
            let pkgPath = "\(nvmVersionsPath)/\(version)/lib/node_modules/\(packageName)/package.json"
            if FileManager.default.fileExists(atPath: pkgPath) {
                return pkgPath
            }
        }
        return nil
    }
    
    private func findPackageJsonInFNM(_ packageName: String, home: String) -> String? {
        let fnmVersionsPath = "\(home)/.fnm/node-versions"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: fnmVersionsPath) else {
            return nil
        }
        
        for version in versions.sorted().reversed() {
            let pkgPath = "\(fnmVersionsPath)/\(version)/installation/lib/node_modules/\(packageName)/package.json"
            if FileManager.default.fileExists(atPath: pkgPath) {
                return pkgPath
            }
        }
        return nil
    }
    
    private func findPackageJsonInAsdf(_ packageName: String, home: String) -> String? {
        let asdfNodePath = "\(home)/.asdf/installs/nodejs"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: asdfNodePath) else {
            return nil
        }
        
        for version in versions.sorted().reversed() {
            let pkgPath = "\(asdfNodePath)/\(version)/lib/node_modules/\(packageName)/package.json"
            if FileManager.default.fileExists(atPath: pkgPath) {
                return pkgPath
            }
        }
        return nil
    }
    
    private func findPackageJsonInVolta(_ packageName: String, home: String) -> String? {
        let voltaPaths = [
            "\(home)/.volta/tools/image/packages/\(packageName)/lib/node_modules/\(packageName)/package.json",
            "\(home)/.volta/tools/image/packages/\(packageName)/node_modules/\(packageName)/package.json",
            "\(home)/.volta/tools/image/node_modules/\(packageName)/package.json"
        ]
        
        for path in voltaPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private func findPackageJsonInPnpm(_ packageName: String, home: String) -> String? {
        let pnpmPath = "\(home)/.local/share/pnpm/global/5/node_modules/\(packageName)/package.json"
        if FileManager.default.fileExists(atPath: pnpmPath) {
            return pnpmPath
        }
        return nil
    }
    
    private func findPackageJsonInBun(_ packageName: String, home: String) -> String? {
        let bunPath = "\(home)/.bun/install/global/node_modules/\(packageName)/package.json"
        if FileManager.default.fileExists(atPath: bunPath) {
            return bunPath
        }
        return nil
    }
    
    func getLatestVersion(_ packageName: String) async -> String? {
        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()
        let result = try? await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/env",
            arguments: ["npm", "view", packageName, "version"],
            environment: shellEnv
        )
        
        guard let result = result, result.succeeded else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func getPluginInfo(_ pluginName: String) async -> OpenCodePluginInfo? {
        guard let known = Self.knownPlugins.first(where: { $0.name == pluginName }) else {
            return nil
        }
        
        let isInstalled = await isInstalled(known.npmPackage)
        let installedVersion = isInstalled ? await getInstalledVersion(known.npmPackage) : nil
        let isRegistered = await configService.isPluginRegistered(pluginName)
        
        return OpenCodePluginInfo(
            name: known.name,
            displayName: known.displayName,
            description: known.description,
            npmPackage: known.npmPackage,
            isInstalled: isInstalled,
            installedVersion: installedVersion,
            latestVersion: nil,
            isRegistered: isRegistered
        )
    }
    
    func getAllPluginInfo() async -> [OpenCodePluginInfo] {
        var infos: [OpenCodePluginInfo] = []
        for known in Self.knownPlugins {
            if let info = await getPluginInfo(known.name) {
                infos.append(info)
            }
        }
        return infos
    }
    
    func install(_ packageName: String, onProgress: ((String) -> Void)? = nil) async throws {
        try validatePackageName(packageName)
        
        guard await checkNpmAvailable() else {
            throw OpenCodePluginError.npmNotFound
        }
        
        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()
        
        let (process, stream) = ProcessExecutor.executeStreaming(
            executable: "/usr/bin/env",
            arguments: ["npm", "install", "-g", packageName, "--progress=false", "--loglevel=verbose"],
            environment: shellEnv
        )
        
        var stderrOutput = ""
        var exitCode: Int32 = 0
        
        defer {
            if process.isRunning {
                process.terminate()
            }
        }
        
        for await output in stream {
            switch output {
            case .stdout(let text):
                onProgress?(text)
            case .stderr(let text):
                onProgress?(text)
                stderrOutput += text
            case .terminated(let code):
                exitCode = code
            case .error(let msg):
                onProgress?("Error: \(msg)\n")
                throw OpenCodePluginError.installFailed(msg)
            }
        }
        
        guard exitCode == 0 else {
            throw OpenCodePluginError.installFailed(stderrOutput)
        }
        
        logger.info("Installed global npm package: \(packageName)")
    }
    
    func uninstall(_ packageName: String) async throws {
        try validatePackageName(packageName)
        
        let shellEnv = await ShellEnvironmentLoader.loadShellEnvironment()
        
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/env",
            arguments: ["npm", "uninstall", "-g", packageName],
            environment: shellEnv
        )
        
        guard result.succeeded else {
            throw OpenCodePluginError.uninstallFailed(result.stderr)
        }
        
        logger.info("Uninstalled global npm package: \(packageName)")
    }
    
    func installAndRegister(_ pluginName: String, onProgress: ((String) -> Void)? = nil) async throws {
        guard let known = Self.knownPlugins.first(where: { $0.name == pluginName }) else {
            throw OpenCodePluginError.installFailed("Unknown plugin: \(pluginName)")
        }
        
        onProgress?("Installing \(known.displayName)...\n")
        try await install(known.npmPackage, onProgress: onProgress)
        
        do {
            onProgress?("\nRegistering plugin in OpenCode config...\n")
            try await configService.registerPlugin(pluginName)
            onProgress?("Done! \(known.displayName) is now active.\n")
        } catch {
            onProgress?("\nRegistration failed. Rolling back installation...\n")
            try? await uninstall(known.npmPackage)
            throw error
        }
    }
    
    func uninstallAndUnregister(_ pluginName: String) async throws {
        guard let known = Self.knownPlugins.first(where: { $0.name == pluginName }) else {
            throw OpenCodePluginError.uninstallFailed("Unknown plugin: \(pluginName)")
        }
        
        try await configService.unregisterPlugin(pluginName)
        try await uninstall(known.npmPackage)
    }
    
    func setPluginEnabled(_ pluginName: String, enabled: Bool) async throws {
        try await configService.setPluginEnabled(pluginName, enabled: enabled)
    }
    
    func validateOMOStatus() async -> (installed: Bool, registered: Bool, message: String?) {
        let isInstalled = await isInstalled("oh-my-opencode")
        let isRegistered = await configService.isPluginRegistered("oh-my-opencode")
        
        var message: String? = nil
        if !isInstalled {
            message = "Oh My OpenCode is not installed. Install it from Settings > Agents > OpenCode > Plugins."
        } else if !isRegistered {
            message = "Oh My OpenCode is installed but not enabled in OpenCode config."
        }
        
        return (isInstalled, isRegistered, message)
    }
}
