import AppKit
import AizenCore
import AizenHost
import Foundation

public struct MacXcodeProjectOpener: XcodeProjectOpening {
    public init() {}

    public func openXcodeProject(at url: URL) async throws {
        guard NSWorkspace.shared.open(url) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}

public struct MacXcodeProjectInspector: XcodeProjectInspecting {
    public init() {}

    public func schemes(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) async throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-list", "-json", kind == .workspace ? "-workspace" : "-project", projectURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let key = kind == .workspace ? "workspace" : "project"
        return (document?[key] as? [String: Any])?["schemes"] as? [String] ?? []
    }
}

public struct MacXcodeProjectBuilder: XcodeProjectBuilding {
    public init() {}
    public func buildXcodeProject(at url: URL, kind: XcodeProjectDescriptor.Kind, scheme: String, destination: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [kind == .workspace ? "-workspace" : "-project", url.path, "-scheme", scheme, "-destination", destination, "build"]
        process.standardOutput = Pipe(); process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableNotLoadable) }
    }
}
