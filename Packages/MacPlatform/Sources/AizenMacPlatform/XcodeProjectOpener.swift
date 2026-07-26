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
        try projectDetails(for: projectURL, kind: kind).schemes
    }

    public func configurations(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) async throws -> [String] {
        try projectDetails(for: projectURL, kind: kind).configurations
    }

    private func projectDetails(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) throws -> (schemes: [String], configurations: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-list", "-json", kind == .workspace ? "-workspace" : "-project", projectURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return ([], []) }
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let key = kind == .workspace ? "workspace" : "project"
        let details = document?[key] as? [String: Any]
        return (details?["schemes"] as? [String] ?? [], details?["configurations"] as? [String] ?? [])
    }
}

public actor MacXcodeProjectBuilder: XcodeProjectBuilding {
    public init() {}
    public func startXcodeProjectBuild(at url: URL, kind: XcodeProjectDescriptor.Kind, scheme: String, destination: String, action: XcodeProjectAction) async throws -> any XcodeBuildRunning {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = Self.arguments(projectURL: url, kind: kind, scheme: scheme, destination: destination, action: action)
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        return MacXcodeBuildProcess(process: process, standardOutput: standardOutput, standardError: standardError)
    }

    static func arguments(projectURL: URL, kind: XcodeProjectDescriptor.Kind, scheme: String, destination: String, action: XcodeProjectAction) -> [String] {
        [kind == .workspace ? "-workspace" : "-project", projectURL.path, "-scheme", scheme, "-destination", destination, action.rawValue]
    }
}

actor MacXcodeBuildProcess: XcodeBuildRunning {
    private let process: XcodeBuildProcessReference
    private let outputStream: AsyncStream<XcodeBuildOutput>
    private let outputContinuation: AsyncStream<XcodeBuildOutput>.Continuation

    init(process: Process) {
        self.init(process: process, standardOutput: Pipe(), standardError: Pipe())
    }

    init(process: Process, standardOutput: Pipe, standardError: Pipe) {
        self.process = .init(process: process)
        var continuation: AsyncStream<XcodeBuildOutput>.Continuation?
        outputStream = AsyncStream { continuation = $0 }
        outputContinuation = continuation!
        Self.forward(standardOutput.fileHandleForReading, stream: .standardOutput, to: outputContinuation)
        Self.forward(standardError.fileHandleForReading, stream: .standardError, to: outputContinuation)
    }

    func waitForCompletion() async throws {
        let status = await Task.detached { [process] in
            process.process.waitUntilExit()
            return process.process.terminationStatus
        }.value
        outputContinuation.finish()
        guard status == 0 else { throw MacXcodeBuildError.failed(status) }
    }

    func output() async -> AsyncStream<XcodeBuildOutput> { outputStream }

    func cancel() {
        guard process.process.isRunning else { return }
        process.process.terminate()
    }

    private nonisolated static func forward(
        _ handle: FileHandle,
        stream: OperationLogChunk.Stream,
        to continuation: AsyncStream<XcodeBuildOutput>.Continuation
    ) {
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            var start = data.startIndex
            while start < data.endIndex {
                let end = min(start + OperationLogChunk.maximumTextUTF8Count, data.endIndex)
                let text = String(decoding: data[start..<end], as: UTF8.self)
                if !text.isEmpty {
                    continuation.yield(.init(stream: stream, text: text))
                }
                start = end
            }
        }
    }
}

private final class XcodeBuildProcessReference: @unchecked Sendable {
    let process: Process

    init(process: Process) {
        self.process = process
    }
}

enum MacXcodeBuildError: LocalizedError, Sendable, Equatable {
    case failed(Int32)

    var errorDescription: String? {
        switch self {
        case let .failed(status): "xcodebuild exited with status \(status)."
        }
    }
}
