//
//  MarkdownImageView.swift
//  aizen
//
//  Markdown image rendering components
//

import SwiftUI

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

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(image.size.width, 600), height: min(image.size.height, 400))
                    .cornerRadius(4)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Failed to load image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let alt = alt, !alt.isEmpty {
                            Text(alt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
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
        let cacheKey = NSString(string: url)
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            await MainActor.run {
                self.image = cached
                self.isLoading = false
            }
            return
        }

        guard let imageURL = URL(string: url) else {
            error = "Invalid URL"
            isLoading = false
            return
        }

        // Check for cancellation before starting
        guard !Task.isCancelled else { return }

        // Check if it's a local file path
        if imageURL.scheme == nil || imageURL.scheme == "file" {
            // Local file
            if let nsImage = NSImage(contentsOfFile: imageURL.path) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
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
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                guard !Task.isCancelled else { return }
                if let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        self.image = nsImage
                        self.isLoading = false
                    }
                    Self.imageCache.setObject(nsImage, forKey: cacheKey, cost: data.count)
                } else {
                    await MainActor.run {
                        self.error = "Invalid image data"
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
}
