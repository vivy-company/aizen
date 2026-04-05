import AppKit
import Foundation

extension ChatTimelineHeaderIconStore {
    static func key(
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

    static func writeRawImageData(_ data: Data, cacheKey: String) -> String? {
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

    static func isSVGData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        let lower = text.lowercased()
        return lower.contains("<svg") || lower.contains("image/svg+xml")
    }

    static func tintColorKey(_ tintColor: NSColor?) -> String {
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

    static func targetPointSizeKey(_ size: CGFloat?) -> String {
        guard let size, size > 0 else { return "default" }
        return String(Int((size * 100).rounded()))
    }

    static func backingScaleKey(_ scale: CGFloat?) -> String {
        guard let scale, scale > 0 else { return "default" }
        return String(Int((scale * 100).rounded()))
    }
}
