//
//  OpenCodeConfigService.swift
//  aizen
//
//  Manages OpenCode's configuration file at ~/.config/opencode/opencode.json
//  Handles plugin registration, not installation (that's OpenCodePluginInstaller's job)
//

import Foundation

enum OpenCodeConfigError: Error, LocalizedError {
    case configNotFound
    case parseError(String)
    case writeError(String)
    case backupFailed
    
    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "OpenCode config file not found at ~/.config/opencode/opencode.json"
        case .parseError(let detail):
            return "Failed to parse OpenCode config: \(detail)"
        case .writeError(let detail):
            return "Failed to write OpenCode config: \(detail)"
        case .backupFailed:
            return "Failed to create config backup"
        }
    }
}

nonisolated struct OpenCodeConfig: Codable {
    var plugin: [String]?
    private var additionalProperties: [String: OpenCodeAnyCodable] = [:]
    
    enum CodingKeys: String, CodingKey {
        case plugin
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plugin = try container.decodeIfPresent([String].self, forKey: .plugin)
        
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        for key in dynamicContainer.allKeys {
            if key.stringValue != "plugin" {
                if let value = try? dynamicContainer.decode(OpenCodeAnyCodable.self, forKey: key) {
                    additionalProperties[key.stringValue] = value
                }
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(plugin, forKey: .plugin)
        
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in additionalProperties {
            if let dynamicKey = DynamicCodingKey(stringValue: key) {
                try dynamicContainer.encode(value, forKey: dynamicKey)
            }
        }
    }
    
    init() {
        self.plugin = nil
    }
}

private nonisolated struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private nonisolated struct OpenCodeAnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([OpenCodeAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: OpenCodeAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { OpenCodeAnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { OpenCodeAnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

actor OpenCodeConfigService {
    static let shared = OpenCodeConfigService()
    
    private let fileManager = FileManager.default
    
    private var configPath: String {
        resolveConfigPath()
    }
    
    private var configDirectory: String {
        resolveConfigDirectory()
    }

    func currentConfigPath() -> String {
        configPath
    }

    func currentConfigDirectory() -> String {
        configDirectory
    }

    func currentOMOConfigPath() -> String {
        (configDirectory as NSString).appendingPathComponent("oh-my-opencode.json")
    }
    
    func configExists() -> Bool {
        fileManager.fileExists(atPath: configPath)
    }
    
    func readConfig() throws -> OpenCodeConfig {
        guard fileManager.fileExists(atPath: configPath) else {
            throw OpenCodeConfigError.configNotFound
        }
        
        guard let data = fileManager.contents(atPath: configPath) else {
            throw OpenCodeConfigError.parseError("Could not read file")
        }
        
        return try decodeConfig(from: data)
    }
    
    func writeConfig(_ config: OpenCodeConfig) throws {
        try ensureConfigDirectory()
        try createBackup()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data: Data
        do {
            data = try encoder.encode(config)
        } catch {
            throw OpenCodeConfigError.writeError(error.localizedDescription)
        }
        
        let tempPath = configPath + ".tmp.\(UUID().uuidString)"
        
        defer {
            try? fileManager.removeItem(atPath: tempPath)
        }
        
        guard fileManager.createFile(atPath: tempPath, contents: data) else {
            throw OpenCodeConfigError.writeError("Failed to create temp file")
        }
        
        do {
            if fileManager.fileExists(atPath: configPath) {
                try fileManager.removeItem(atPath: configPath)
            }
            try fileManager.moveItem(atPath: tempPath, toPath: configPath)
        } catch {
            throw OpenCodeConfigError.writeError(error.localizedDescription)
        }
    }
    
    func getRegisteredPlugins() -> [String] {
        guard let config = try? readConfig() else {
            return []
        }
        return config.plugin ?? []
    }
    
    func isPluginRegistered(_ pluginName: String) -> Bool {
        let plugins = getRegisteredPlugins()
        return plugins.contains { entry in
            entry == pluginName || entry.hasPrefix(pluginName + "@")
        }
    }
    
    func registerPlugin(_ pluginName: String) throws {
        var config: OpenCodeConfig
        do {
            config = try readConfig()
        } catch OpenCodeConfigError.configNotFound {
            config = OpenCodeConfig()
        } catch OpenCodeConfigError.parseError {
            let backupPath = configPath + ".backup"
            if fileManager.fileExists(atPath: backupPath) {
                do {
                    try restoreBackup()
                    config = try readConfig()
                } catch {
                    config = OpenCodeConfig()
                }
            } else {
                config = OpenCodeConfig()
            }
        } catch {
            throw error
        }
        
        var plugins = config.plugin ?? []
        
        let alreadyRegistered = plugins.contains { entry in
            entry == pluginName || entry.hasPrefix(pluginName + "@")
        }
        guard !alreadyRegistered else {
            return
        }
        
        plugins.append(pluginName)
        config.plugin = plugins
        
        try writeConfig(config)
    }
    
    func unregisterPlugin(_ pluginName: String) throws {
        var config = try readConfig()
        
        guard var plugins = config.plugin else { return }
        
        let originalCount = plugins.count
        plugins.removeAll { entry in
            entry == pluginName || entry.hasPrefix(pluginName + "@")
        }
        
        guard plugins.count != originalCount else { return }
        
        config.plugin = plugins.isEmpty ? nil : plugins
        
        try writeConfig(config)
    }
    
    func setPluginEnabled(_ pluginName: String, enabled: Bool) throws {
        if enabled {
            try registerPlugin(pluginName)
        } else {
            try unregisterPlugin(pluginName)
        }
    }
    
    private func ensureConfigDirectory() throws {
        if !fileManager.fileExists(atPath: configDirectory) {
            try fileManager.createDirectory(atPath: configDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func createBackup() throws {
        guard fileManager.fileExists(atPath: configPath) else { return }
        
        let backupPath = configPath + ".backup"
        
        if fileManager.fileExists(atPath: backupPath) {
            try? fileManager.removeItem(atPath: backupPath)
        }
        
        try fileManager.copyItem(atPath: configPath, toPath: backupPath)
    }
    
    func restoreBackup() throws {
        let backupPath = configPath + ".backup"
        guard fileManager.fileExists(atPath: backupPath) else {
            throw OpenCodeConfigError.backupFailed
        }
        
        if fileManager.fileExists(atPath: configPath) {
            try fileManager.removeItem(atPath: configPath)
        }
        
        try fileManager.moveItem(atPath: backupPath, toPath: configPath)
    }
    
    private func decodeConfig(from data: Data) throws -> OpenCodeConfig {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(OpenCodeConfig.self, from: data)
        } catch {
            guard let text = String(data: data, encoding: .utf8) else {
                throw OpenCodeConfigError.parseError(error.localizedDescription)
            }
            let stripped = removeTrailingCommas(from: stripJSONC(text))
            guard let cleanedData = stripped.data(using: .utf8) else {
                throw OpenCodeConfigError.parseError(error.localizedDescription)
            }
            do {
                return try decoder.decode(OpenCodeConfig.self, from: cleanedData)
            } catch {
                throw OpenCodeConfigError.parseError(error.localizedDescription)
            }
        }
    }

    private func resolveConfigPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["OPENCODE_CONFIG"], !explicit.isEmpty {
            return expandTilde(explicit)
        }
        if let dir = env["OPENCODE_CONFIG_DIR"], !dir.isEmpty {
            let resolvedDir = expandTilde(dir)
            return (resolvedDir as NSString).appendingPathComponent("opencode.json")
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        return "\(home)/.config/opencode/opencode.json"
    }

    private func resolveConfigDirectory() -> String {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["OPENCODE_CONFIG_DIR"], !dir.isEmpty {
            return expandTilde(dir)
        }
        if let explicit = env["OPENCODE_CONFIG"], !explicit.isEmpty {
            return (expandTilde(explicit) as NSString).deletingLastPathComponent
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        return "\(home)/.config/opencode"
    }

    private func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func stripJSONC(_ input: String) -> String {
        let chars = Array(input)
        var output: [Character] = []
        var i = 0
        var inString = false
        var isEscaped = false
        var inSingleLineComment = false
        var inMultiLineComment = false

        while i < chars.count {
            let ch = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil

            if inSingleLineComment {
                if ch == "\n" {
                    inSingleLineComment = false
                    output.append(ch)
                }
                i += 1
                continue
            }

            if inMultiLineComment {
                if ch == "*" && next == "/" {
                    inMultiLineComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            if inString {
                output.append(ch)
                if isEscaped {
                    isEscaped = false
                } else if ch == "\\" {
                    isEscaped = true
                } else if ch == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            if ch == "\"" {
                inString = true
                output.append(ch)
                i += 1
                continue
            }

            if ch == "/" && next == "/" {
                inSingleLineComment = true
                i += 2
                continue
            }

            if ch == "/" && next == "*" {
                inMultiLineComment = true
                i += 2
                continue
            }

            output.append(ch)
            i += 1
        }

        return String(output)
    }

    private func removeTrailingCommas(from input: String) -> String {
        let chars = Array(input)
        var output: [Character] = []
        var i = 0
        var inString = false
        var isEscaped = false

        while i < chars.count {
            let ch = chars[i]

            if inString {
                output.append(ch)
                if isEscaped {
                    isEscaped = false
                } else if ch == "\\" {
                    isEscaped = true
                } else if ch == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            if ch == "\"" {
                inString = true
                output.append(ch)
                i += 1
                continue
            }

            if ch == "," {
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace {
                    j += 1
                }
                if j < chars.count, (chars[j] == "}" || chars[j] == "]") {
                    i += 1
                    continue
                }
            }

            output.append(ch)
            i += 1
        }

        return String(output)
    }
}
