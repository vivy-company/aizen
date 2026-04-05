import AppKit
import Foundation

extension ChatTimelineHeaderIconStore {
    static func writeRasterImage(
        _ image: NSImage,
        cacheKey: String,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> String? {
        guard let data = rasterizedPNGData(
            for: image,
            tintColor: tintColor,
            targetPointSize: targetPointSize,
            backingScale: backingScale
        ) else {
            return nil
        }
        let fileURL = directoryURL.appendingPathComponent("\(cacheKey).png")
        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return nil
            }
        }
        return fileURL.path
    }

    static func rasterizedPNGData(
        for image: NSImage,
        tintColor: NSColor?,
        targetPointSize: CGFloat?,
        backingScale: CGFloat?
    ) -> Data? {
        let sourceSize = normalizedSourceSize(for: image)
        let renderPointSize = resolvedRenderPointSize(
            sourceSize: sourceSize,
            targetPointSize: targetPointSize
        )
        let scale = max(1, backingScale ?? NSScreen.main?.backingScaleFactor ?? 2)
        let pixelWidth = max(1, Int((renderPointSize.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((renderPointSize.height * scale).rounded(.up)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmap.size = renderPointSize

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let bounds = NSRect(origin: .zero, size: renderPointSize)
        NSColor.clear.setFill()
        bounds.fill()

        let drawRect = aspectFitRect(contentSize: sourceSize, in: bounds)
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)

        if let tintColor {
            tintColor.setFill()
            bounds.fill(using: .sourceIn)
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    static func normalizedSourceSize(for image: NSImage) -> NSSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           cgImage.width > 0, cgImage.height > 0 {
            let scale = image.representations
                .compactMap { $0.pixelsWide > 0 ? CGFloat($0.pixelsWide) / max(1, $0.size.width) : nil }
                .max() ?? NSScreen.main?.backingScaleFactor ?? 2
            return NSSize(width: CGFloat(cgImage.width) / max(1, scale), height: CGFloat(cgImage.height) / max(1, scale))
        }
        if image.size.width > 0 && image.size.height > 0 {
            return image.size
        }
        return NSSize(width: 16, height: 16)
    }

    static func resolvedRenderPointSize(sourceSize: NSSize, targetPointSize: CGFloat?) -> NSSize {
        guard let targetPointSize, targetPointSize > 0 else {
            return sourceSize
        }
        return NSSize(width: targetPointSize, height: targetPointSize)
    }

    static func aspectFitRect(contentSize: NSSize, in bounds: NSRect) -> NSRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return bounds }
        let widthRatio = bounds.width / contentSize.width
        let heightRatio = bounds.height / contentSize.height
        let scale = min(widthRatio, heightRatio)
        let drawSize = NSSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return NSRect(
            x: bounds.minX + (bounds.width - drawSize.width) * 0.5,
            y: bounds.minY + (bounds.height - drawSize.height) * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    static func configuredSymbolImage(_ image: NSImage, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage {
        let config = NSImage.SymbolConfiguration(
            pointSize: max(12, pointSize),
            weight: weight,
            scale: .medium
        )
        return image.withSymbolConfiguration(config) ?? image
    }
}
