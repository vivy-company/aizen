import AppKit
import Foundation

enum ChatTimelineHeaderIconStore {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()
    static let fileManager = FileManager.default
    private static let renderVersion = "v5"
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

    private static func key(
        for iconType: AgentIconType,
        fallbackAgentId: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> String {
        let tintKey = tintColorKey(tintColor)
        let sizeKey = targetPointSizeKey(targetPointSize)
        let scaleKey = backingScaleKey(backingScale)
        switch iconType {
        case .builtin(let name):
            return "\(renderVersion)-builtin-\(name.lowercased())-\(sizeKey)-\(scaleKey)-\(tintKey)"
        case .sfSymbol(let symbol):
            return "\(renderVersion)-sf-\(symbol)-\(sizeKey)-\(scaleKey)-\(tintKey)"
        case .customImage(let data):
            return "\(renderVersion)-custom-\(data.hashValue)-\(sizeKey)-\(scaleKey)-\(tintKey)"
        }
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

    private static func writeRawImageData(_ data: Data, cacheKey: String) -> String? {
        let ext = isSVGData(data) ? "svg" : "img"
        let fileURL = directoryURL.appendingPathComponent("\(cacheKey).\(ext)")

        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return nil
            }
        }

        return fileURL.path
    }

    private static func isSVGData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        let lower = text.lowercased()
        return lower.contains("<svg") || lower.contains("image/svg+xml")
    }

    private static func tintColorKey(_ tintColor: NSColor?) -> String {
        guard let tintColor,
              let color = tintColor.usingColorSpace(.sRGB) else {
            return "notint"
        }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        let a = Int((color.alphaComponent * 255).rounded())
        return "\(r)-\(g)-\(b)-\(a)"
    }

    private static func targetPointSizeKey(_ size: CGFloat?) -> String {
        guard let size, size > 0 else { return "default" }
        return String(Int((size * 100).rounded()))
    }

    private static func backingScaleKey(_ scale: CGFloat?) -> String {
        guard let scale, scale > 0 else { return "default" }
        return String(Int((scale * 100).rounded()))
    }
}
