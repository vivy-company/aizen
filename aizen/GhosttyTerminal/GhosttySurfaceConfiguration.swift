import AppKit
import GhosttyKit

extension Ghostty {
    /// Copied from Ghostty's SurfaceView.swift and adapted to Aizen's active terminal view type.
    struct SurfaceConfiguration {
        var fontSize: Float32?
        var workingDirectory: String?
        var command: String?
        var environmentVariables: [String: String] = [:]
        var initialInput: String?
        var waitAfterCommand: Bool = false
        var context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_WINDOW

        init() {}

        init(from config: ghostty_surface_config_s) {
            self.fontSize = config.font_size
            if let workingDirectory = config.working_directory {
                self.workingDirectory = String(cString: workingDirectory, encoding: .utf8)
            }
            if let command = config.command {
                self.command = String(cString: command, encoding: .utf8)
            }

            if config.env_var_count > 0, let envVars = config.env_vars {
                for i in 0..<config.env_var_count {
                    let envVar = envVars[i]
                    if let key = String(cString: envVar.key, encoding: .utf8),
                       let value = String(cString: envVar.value, encoding: .utf8) {
                        self.environmentVariables[key] = value
                    }
                }
            }

            self.context = config.context
        }

        func withCValue<T>(
            view: NSView,
            _ body: (inout ghostty_surface_config_s) throws -> T
        ) rethrows -> T {
            var config = ghostty_surface_config_new()
            config.userdata = Unmanaged.passUnretained(view).toOpaque()
            config.platform_tag = GHOSTTY_PLATFORM_MACOS
            config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(view).toOpaque()
            ))
            config.scale_factor = Double(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            config.font_size = fontSize ?? 0
            config.wait_after_command = waitAfterCommand
            config.context = context

            return try workingDirectory.withCString { cWorkingDir in
                config.working_directory = cWorkingDir

                return try command.withCString { cCommand in
                    config.command = cCommand

                    return try initialInput.withCString { cInput in
                        config.initial_input = cInput

                        let keys = Array(environmentVariables.keys)
                        let values = Array(environmentVariables.values)

                        return try keys.withCStrings { keyCStrings in
                            try values.withCStrings { valueCStrings in
                                var envVars = [ghostty_env_var_s]()
                                envVars.reserveCapacity(environmentVariables.count)
                                for i in 0..<environmentVariables.count {
                                    envVars.append(ghostty_env_var_s(
                                        key: keyCStrings[i],
                                        value: valueCStrings[i]
                                    ))
                                }

                                return try envVars.withUnsafeMutableBufferPointer { buffer in
                                    config.env_vars = buffer.baseAddress
                                    config.env_var_count = environmentVariables.count
                                    return try body(&config)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

extension Array where Element == String {
    /// Copied from Ghostty's Array+Extension.swift.
    func withCStrings<T>(_ body: ([UnsafePointer<Int8>?]) throws -> T) rethrows -> T {
        if isEmpty {
            return try body([])
        }

        func helper(
            index: Int,
            accumulated: [UnsafePointer<Int8>?],
            body: ([UnsafePointer<Int8>?]) throws -> T
        ) rethrows -> T {
            if index == count {
                return try body(accumulated)
            }

            return try self[index].withCString { cStr in
                var newAccumulated = accumulated
                newAccumulated.append(cStr)
                return try helper(index: index + 1, accumulated: newAccumulated, body: body)
            }
        }

        return try helper(index: 0, accumulated: [], body: body)
    }
}

private extension Optional where Wrapped == String {
    func withCString<T>(_ body: (UnsafePointer<CChar>?) throws -> T) rethrows -> T {
        switch self {
        case .some(let string):
            return try string.withCString(body)
        case .none:
            return try body(nil)
        }
    }
}
