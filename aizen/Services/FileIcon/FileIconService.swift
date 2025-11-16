//
//  FileIconService.swift
//  aizen
//
//  Thread-safe service for loading and caching file type icons.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

actor FileIconService {
    // MARK: - Singleton

    static let shared = FileIconService()

    // MARK: - Cache

    private let cache = NSCache<NSString, NSImage>()

    // MARK: - Initialization

    private init() {
        // Configure cache limits
        cache.countLimit = 1000 // Max 1000 icons
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }

    // MARK: - Public API

    /// Loads the icon for a file path with caching
    /// - Parameters:
    ///   - filePath: The file path
    ///   - size: The desired icon size (default: 16x16)
    /// - Returns: The icon image, or nil if not found
    func icon(forFile filePath: String, size: CGSize = CGSize(width: 16, height: 16)) -> NSImage? {
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory), isDirectory.boolValue {
            return folderIcon(size: size)
        }

        // Try to get file type icon
        guard let iconName = FileIconMapper.iconName(for: filePath) else {
            return defaultFileIcon(size: size)
        }

        return icon(named: iconName, size: size)
    }

    /// Loads an icon by name with caching
    /// - Parameters:
    ///   - iconName: The icon name (e.g., "file_swift")
    ///   - size: The desired icon size
    /// - Returns: The icon image, or nil if not found
    func icon(named iconName: String, size: CGSize) -> NSImage? {
        let cacheKey = "\(iconName)_\(Int(size.width))x\(Int(size.height))" as NSString

        // Check cache first
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Load from asset catalog
        guard let icon = NSImage(named: iconName) else {
            return nil
        }

        // Resize if needed
        let resizedIcon = icon.resized(to: size)

        // Cache it (cost = approximate bytes)
        let cost = Int(size.width * size.height * 4)
        cache.setObject(resizedIcon, forKey: cacheKey, cost: cost)

        return resizedIcon
    }

    /// Clears the icon cache
    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Private Helpers

    private func folderIcon(size: CGSize) -> NSImage {
        // Use Catppuccin folder icon instead of system icon
        if let catppuccinFolder = icon(named: "file_folder", size: size) {
            return catppuccinFolder
        }

        // Fallback to system folder icon if Catppuccin icon not found
        let cacheKey = "folder_\(Int(size.width))x\(Int(size.height))" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(for: .folder)
        let resizedIcon = icon.resized(to: size)

        let cost = Int(size.width * size.height * 4)
        cache.setObject(resizedIcon, forKey: cacheKey, cost: cost)

        return resizedIcon
    }

    private func defaultFileIcon(size: CGSize) -> NSImage {
        // Use Catppuccin default file icon instead of system icon
        if let catppuccinFile = icon(named: "file_default", size: size) {
            return catppuccinFile
        }

        // Fallback to system file icon if Catppuccin icon not found
        let cacheKey = "default_file_\(Int(size.width))x\(Int(size.height))" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFileType: "public.data")
        let resizedIcon = icon.resized(to: size)

        let cost = Int(size.width * size.height * 4)
        cache.setObject(resizedIcon, forKey: cacheKey, cost: cost)

        return resizedIcon
    }
}

// MARK: - NSImage Extension

extension NSImage {
    /// Resizes the image to the target size
    /// - Parameter targetSize: The target size
    /// - Returns: A new resized image
    func resized(to targetSize: CGSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }

        let sourceRect = NSRect(origin: .zero, size: size)
        let targetRect = NSRect(origin: .zero, size: targetSize)

        draw(in: targetRect, from: sourceRect, operation: .copy, fraction: 1.0)

        return newImage
    }
}
