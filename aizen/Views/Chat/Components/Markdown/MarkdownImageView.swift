//
//  MarkdownImageView.swift
//  aizen
//
//  Markdown image rendering components
//

import SwiftUI
import WebKit

// MARK: - Image Row Item

struct ImageRowItem: Identifiable {
    let id: String
    let url: String
    let alt: String?

    init(index: Int, url: String, alt: String?) {
        self.url = url
        self.alt = alt
        self.id = "imgrow-item-\(index)-\(url.hashValue)"
    }
}

// MARK: - Markdown Image Row View

struct MarkdownImageRowView: View {
    let images: [(url: String, alt: String?)]

    private var wrappedImages: [ImageRowItem] {
        images.enumerated().map { ImageRowItem(index: $0.offset, url: $0.element.url, alt: $0.element.alt) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(wrappedImages) { item in
                MarkdownImageView(url: item.url, alt: item.alt)
            }
        }
    }
}

// MARK: - Markdown Image View

struct MarkdownImageView: View {
    let url: String
    let alt: String?
    var basePath: String? = nil  // Base path for resolving relative URLs

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var error: String?
    @State private var loadTask: Task<Void, Never>?
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    /// Resolve URL, handling relative paths if basePath is provided
    private var resolvedURL: String {
        // If URL is already absolute (has scheme), use as-is
        if url.hasPrefix("http://") || url.hasPrefix("https://") || url.hasPrefix("file://") {
            return url
        }

        // If we have a basePath, resolve relative URL
        if let basePath = basePath {
            let baseURL = URL(fileURLWithPath: basePath, isDirectory: true)
            if let resolved = URL(string: url, relativeTo: baseURL) {
                return resolved.absoluteString
            }
            // Try as file path
            let resolvedPath = (basePath as NSString).appendingPathComponent(url)
            return resolvedPath
        }

        return url
    }

    // Track the loaded image size to maintain stable layout
    @State private var loadedSize: CGSize?

    // Default placeholder size for badges (most common case)
    private let placeholderSize = CGSize(width: 80, height: 20)

    @ViewBuilder
    private var content: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(4)
        } else if isLoading {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .overlay(
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                )
        } else {
            // Error state
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                )
                .help(error ?? "Failed to load")
        }
    }

    var body: some View {
        content
            // Use fixed frame based on loaded size, or badge-like placeholder size
            .frame(
                width: loadedSize?.width ?? placeholderSize.width,
                height: loadedSize?.height ?? placeholderSize.height
            )
        .onAppear {
            // Start loading only if not already loaded
            guard loadTask == nil && image == nil else { return }
            loadTask = Task {
                await loadImage()
            }
        }
        .onDisappear {
            // Cancel loading when view disappears (scrolled off-screen)
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadImage() async {
        let urlToLoad = resolvedURL
        let cacheKey = NSString(string: urlToLoad)
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            let size = calculateDisplaySize(for: cached)
            await MainActor.run {
                self.loadedSize = size
                self.image = cached
                self.isLoading = false
            }
            return
        }

        // Try as file path first (for local files)
        let fileURL = URL(fileURLWithPath: urlToLoad)
        let imageURL: URL
        if FileManager.default.fileExists(atPath: urlToLoad) {
            imageURL = fileURL
        } else if let parsedURL = URL(string: urlToLoad) {
            imageURL = parsedURL
        } else {
            await MainActor.run {
                self.error = "Invalid URL"
                self.isLoading = false
            }
            return
        }

        // Check for cancellation before starting
        guard !Task.isCancelled else { return }

        // Check if it's a local file path
        if imageURL.scheme == nil || imageURL.scheme == "file" {
            // Local file
            if let nsImage = NSImage(contentsOfFile: imageURL.path) {
                guard !Task.isCancelled else { return }
                let size = calculateDisplaySize(for: nsImage)
                await MainActor.run {
                    self.loadedSize = size
                    self.image = nsImage
                    self.isLoading = false
                }
                let cost = nsImage.tiffRepresentation?.count ?? 0
                Self.imageCache.setObject(nsImage, forKey: cacheKey, cost: cost)
            } else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = "File not found"
                    self.isLoading = false
                }
            }
        } else {
            // Remote URL
            do {
                let (data, response) = try await URLSession.shared.data(from: imageURL)
                guard !Task.isCancelled else { return }

                // Check if it's SVG content
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
                let isSVG = contentType.contains("svg") || (data.count < 50000 && String(data: data.prefix(200), encoding: .utf8)?.contains("<svg") == true)

                if isSVG {
                    // Try native NSImage first (macOS 10.15+ has _NSSVGImageRep)
                    if let nsImage = NSImage(data: data), nsImage.size.width > 0, nsImage.size.height > 0 {
                        guard !Task.isCancelled else { return }
                        let size = calculateDisplaySize(for: nsImage)
                        await MainActor.run {
                            self.loadedSize = size
                            self.image = nsImage
                            self.isLoading = false
                        }
                        Self.imageCache.setObject(nsImage, forKey: cacheKey, cost: data.count)
                        return
                    }

                    // Fallback to WebKit rendering for complex SVGs
                    if let (svgImage, svgSize) = await SVGRenderer.shared.render(svgData: data, cacheKey: urlToLoad) {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            self.loadedSize = svgSize
                            self.image = svgImage
                            self.isLoading = false
                        }
                        Self.imageCache.setObject(svgImage, forKey: cacheKey, cost: data.count)
                    } else {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            self.loadedSize = CGSize(width: 100, height: 20)
                            self.error = "SVG render failed"
                            self.isLoading = false
                        }
                    }
                    return
                }

                if let nsImage = NSImage(data: data) {
                    let size = calculateDisplaySize(for: nsImage)
                    await MainActor.run {
                        self.loadedSize = size
                        self.image = nsImage
                        self.isLoading = false
                    }
                    Self.imageCache.setObject(nsImage, forKey: cacheKey, cost: data.count)
                } else {
                    await MainActor.run {
                        self.error = "Invalid image"
                        self.isLoading = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func calculateDisplaySize(for image: NSImage) -> CGSize {
        let maxWidth: CGFloat = 600
        let maxHeight: CGFloat = 400
        let size = image.size

        if size.width <= maxWidth && size.height <= maxHeight {
            return size
        }

        let widthRatio = maxWidth / size.width
        let heightRatio = maxHeight / size.height
        let ratio = min(widthRatio, heightRatio)

        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }
}

// MARK: - SVG Renderer

/// Renders SVG data to NSImage using WebKit
actor SVGRenderer {
    static let shared = SVGRenderer()

    private var cache = NSCache<NSString, CachedSVG>()
    // Keep active renderers alive until they complete
    private var activeRenderers: [ObjectIdentifier: SVGWebRenderer] = [:]

    private class CachedSVG: NSObject {
        let image: NSImage
        let size: CGSize

        init(image: NSImage, size: CGSize) {
            self.image = image
            self.size = size
        }
    }

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 20 * 1024 * 1024
    }

    func render(svgData: Data, cacheKey: String) async -> (NSImage, CGSize)? {
        let key = NSString(string: cacheKey)

        if let cached = cache.object(forKey: key) {
            return (cached.image, cached.size)
        }

        // Use withCheckedContinuation with proper cleanup
        let result: (NSImage, CGSize)? = await withCheckedContinuation { continuation in
            var hasResumed = false

            Task { @MainActor in
                let renderer = SVGWebRenderer()
                let rendererId = ObjectIdentifier(renderer)

                // Store the renderer to keep it alive
                await self.registerRenderer(renderer, id: rendererId)

                renderer.render(svgData: svgData) { [weak renderer] result in
                    guard !hasResumed else { return }
                    hasResumed = true

                    Task {
                        await self.unregisterRenderer(rendererId)
                    }

                    continuation.resume(returning: result)
                }

                // Fallback timeout to ensure continuation is always resumed
                Task {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    guard !hasResumed else { return }
                    hasResumed = true
                    await self.unregisterRenderer(rendererId)
                    continuation.resume(returning: nil)
                }
            }
        }

        // Cache successful results
        if let (image, size) = result {
            let cached = CachedSVG(image: image, size: size)
            cache.setObject(cached, forKey: key)
        }

        return result
    }

    private func registerRenderer(_ renderer: SVGWebRenderer, id: ObjectIdentifier) {
        activeRenderers[id] = renderer
    }

    private func unregisterRenderer(_ id: ObjectIdentifier) {
        activeRenderers.removeValue(forKey: id)
    }
}

// MARK: - SVG Web Renderer

@MainActor
class SVGWebRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var completion: (((NSImage, CGSize)?) -> Void)?
    private var hasCompleted = false

    override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 200), configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    private func complete(with result: (NSImage, CGSize)?) {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion?(result)
        completion = nil
    }

    func render(svgData: Data, completion: @escaping ((NSImage, CGSize)?) -> Void) {
        self.completion = completion
        self.hasCompleted = false

        guard let svgString = String(data: svgData, encoding: .utf8) else {
            complete(with: nil)
            return
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; }
                html, body { background: transparent; }
                body { display: inline-block; }
                svg { display: block; max-width: 600px; height: auto; }
            </style>
        </head>
        <body>
            \(svgString)
            <script>
                setTimeout(function() {
                    var svg = document.querySelector('svg');
                    if (svg) {
                        var rect = svg.getBoundingClientRect();
                        document.title = Math.ceil(rect.width) + 'x' + Math.ceil(rect.height);
                    }
                }, 100);
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.captureImage()
        }
    }

    private func captureImage() {
        guard !hasCompleted else { return }

        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            guard let self = self, !self.hasCompleted else { return }

            var width: CGFloat = 100
            var height: CGFloat = 20

            if let title = result as? String, title.contains("x") {
                let parts = title.split(separator: "x")
                if parts.count == 2,
                   let w = Double(parts[0]),
                   let h = Double(parts[1]) {
                    width = CGFloat(w)
                    height = CGFloat(h)
                }
            }

            width = min(width + 4, 600)
            height = min(height + 4, 400)

            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: width, height: height)

            self.webView.takeSnapshot(with: config) { [weak self] image, _ in
                if let image = image {
                    self?.complete(with: (image, CGSize(width: width, height: height)))
                } else {
                    self?.complete(with: nil)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        complete(with: nil)
    }
}
