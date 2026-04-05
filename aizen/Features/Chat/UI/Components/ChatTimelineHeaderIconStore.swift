import AppKit
import Foundation

enum ChatTimelineHeaderIconStore {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()
    static let fileManager = FileManager.default
    static let renderVersion = "v5"
    static let directoryURL: URL = {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("aizen-chat-header-icons", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func urlString(for iconType: AgentIconType, fallbackAgentId: String) -> String? {
        urlString(for: iconType, fallbackAgentId: fallbackAgentId, tintColor: nil)
    }

    static func urlString(
        for iconType: AgentIconType,
        fallbackAgentId: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat? = nil,
        backingScale: CGFloat? = nil
    ) -> String? {
        let cacheKey = key(
            for: iconType,
            fallbackAgentId: fallbackAgentId,
            tintColor: tintColor,
            targetPointSize: targetPointSize,
            backingScale: backingScale
        )

        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let path = iconPath(
            for: iconType,
            fallbackAgentId: fallbackAgentId,
            cacheKey: cacheKey,
            tintColor: tintColor,
            targetPointSize: targetPointSize,
            backingScale: backingScale
        ) else {
            return nil
        }

        lock.lock()
        cache[cacheKey] = path
        lock.unlock()
        return path
    }

    private static func iconPath(
        for iconType: AgentIconType,
        fallbackAgentId: String,
        cacheKey: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> String? {
        switch iconType {
        case .builtin:
            guard let image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: nil) else {
                return nil
            }
            return writeRasterImage(
                image,
                cacheKey: cacheKey,
                tintColor: tintColor,
                targetPointSize: targetPointSize,
                backingScale: backingScale
            )
        case .sfSymbol(let symbol):
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
                return nil
            }
            let configured = configuredSymbolImage(
                image,
                pointSize: max(12, targetPointSize ?? 19),
                weight: .regular
            )
            return writeRasterImage(
                configured,
                cacheKey: cacheKey,
                tintColor: tintColor,
                targetPointSize: targetPointSize,
                backingScale: backingScale
            )
        case .customImage(let data):
            if let image = NSImage(data: data) {
                return writeRasterImage(
                    image,
                    cacheKey: cacheKey,
                    tintColor: tintColor,
                    targetPointSize: targetPointSize,
                    backingScale: backingScale
                )
            }
            return writeRawImageData(data, cacheKey: cacheKey)
        }
    }
}
