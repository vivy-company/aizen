//
//  RegistryAgentIconCache.swift
//  aizen
//

import CryptoKit
import Foundation

actor RegistryAgentIconCache {
    static let shared = RegistryAgentIconCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectory = baseDirectory.appendingPathComponent("agent-registry-icons", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func iconData(for urlString: String?) async -> Data? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let fileURL = cachedFileURL(for: urlString)

        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            return data
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  !data.isEmpty else {
                return nil
            }
            try data.write(to: fileURL, options: .atomic)
            return data
        } catch {
            return nil
        }
    }

    nonisolated static func isSVGData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        let lower = text.lowercased()
        return lower.contains("<svg") || lower.contains("image/svg+xml")
    }

    private func cachedFileURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        let ext = URL(string: urlString)?.pathExtension.isEmpty == false ? (URL(string: urlString)?.pathExtension ?? "img") : "img"
        return cacheDirectory.appendingPathComponent("\(hex).\(ext)")
    }
}
