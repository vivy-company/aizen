import Foundation

extension CodexRPCClient {
    static func makeStdoutLineStream() -> (
        stream: AsyncStream<Data>,
        continuation: AsyncStream<Data>.Continuation
    ) {
        var stdoutContinuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data> { continuation in
            stdoutContinuation = continuation
        }
        return (stream, stdoutContinuation)
    }

    func configureAndLaunchProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) throws {
        let resolvedExec = resolveCodexBinary(executable: executable, environment: environment)
        guard let resolvedExec else {
            throw RPCWireError.startFailed("Codex CLI not found. Install the codex agent and retry.")
        }

        var env = environment ?? ProcessInfo.processInfo.environment
        env["PATH"] = mergedPATH(
            primary: env["PATH"],
            secondary: ProcessInfo.processInfo.environment["PATH"],
            extras: ["/opt/homebrew/bin", "/usr/local/bin"]
        )

        process.environment = env
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [resolvedExec] + arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RPCWireError.startFailed(error.localizedDescription)
        }
    }

    func installReadabilityHandlers() {
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stdoutLineContinuation = stdoutLineContinuation
        let stdoutBuffer = LineBuffer()
        stdoutHandle.readabilityHandler = { handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    stdoutLineContinuation.finish()
                    return
                }
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    stdoutLineContinuation.finish()
                    return
                }

                let lines = stdoutBuffer.appendAndDrainLines(data)
                for lineData in lines {
                    stdoutLineContinuation.yield(lineData)
                }
            } catch {
                handle.readabilityHandler = nil
                stdoutLineContinuation.finish()
            }
        }

        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                for line in text.split(whereSeparator: \.isNewline) {
                    self.recordStderr(String(line))
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }
    }

    func terminateProcessIfRunning() {
        if process.isRunning {
            process.terminate()
        }
    }
}

func resolveCodexBinary(executable: String, environment: [String: String]?) -> String? {
    let env = environment ?? ProcessInfo.processInfo.environment
    if let override = env["CODEX_CLI_PATH"], FileManager.default.isExecutableFile(atPath: override) {
        return override
    }
    let merged = mergedPATH(
        primary: env["PATH"],
        secondary: ProcessInfo.processInfo.environment["PATH"],
        extras: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    )
    for dir in merged.split(separator: ":") {
        let candidate = "\(dir)/\(executable)"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

func mergedPATH(primary: String?, secondary: String?, extras: [String]) -> String {
    var parts: [String] = []
    if let primary, !primary.isEmpty {
        parts.append(contentsOf: primary.split(separator: ":").map(String.init))
    }
    if let secondary, !secondary.isEmpty {
        parts.append(contentsOf: secondary.split(separator: ":").map(String.init))
    }
    parts.append(contentsOf: extras)

    if parts.isEmpty {
        parts = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    var seen = Set<String>()
    let deduped = parts.compactMap { part -> String? in
        guard !part.isEmpty else { return nil }
        if seen.insert(part).inserted {
            return part
        }
        return nil
    }
    return deduped.joined(separator: ":")
}
