//
//  FileService.swift
//  aizen
//
//  File operations service with atomic write support
//

import Foundation

enum FileServiceError: LocalizedError {
    case invalidPath
    case writePermissionDenied
    case writeFailed(String)
    case fileNotFound
    case fileAlreadyExists
    case createFailed(String)
    case deleteFailed(String)
    case renameFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Invalid file path"
        case .writePermissionDenied:
            return "Permission denied. Cannot write to this file"
        case .writeFailed(let details):
            return "Failed to save file: \(details)"
        case .fileNotFound:
            return "File not found"
        case .fileAlreadyExists:
            return "File or folder already exists"
        case .createFailed(let details):
            return "Failed to create: \(details)"
        case .deleteFailed(let details):
            return "Failed to delete: \(details)"
        case .renameFailed(let details):
            return "Failed to rename: \(details)"
        }
    }
}

actor FileService {
    private let fileManager = FileManager.default

    // MARK: - Public Methods

    /// Saves content to a file using atomic write for safety
    /// - Parameters:
    ///   - path: Absolute path to the file
    ///   - content: Content to write
    /// - Throws: FileServiceError if save fails
    func saveFile(path: String, content: String) async throws {
        // Validate path
        guard !path.isEmpty else {
            throw FileServiceError.invalidPath
        }

        let fileURL = URL(fileURLWithPath: path)

        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            throw FileServiceError.fileNotFound
        }

        // Check write permissions
        guard fileManager.isWritableFile(atPath: path) else {
            throw FileServiceError.writePermissionDenied
        }

        // Atomic write: write to temp file, then rename
        do {
            // Create temp file in same directory for atomic rename
            let directory = fileURL.deletingLastPathComponent()
            let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")

            // Get original file attributes to preserve permissions
            let attributes = try fileManager.attributesOfItem(atPath: path)

            // Write to temp file
            try content.write(to: tempURL, atomically: false, encoding: .utf8)

            // Preserve original permissions
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: tempURL.path)
            }

            // Atomic rename (replaces original file)
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)

        } catch let error as FileServiceError {
            throw error
        } catch {
            throw FileServiceError.writeFailed(error.localizedDescription)
        }
    }

    /// Reads file content
    /// - Parameter path: Absolute path to the file
    /// - Returns: File content as string
    /// - Throws: FileServiceError if read fails
    func readFile(path: String) async throws -> String {
        guard !path.isEmpty else {
            throw FileServiceError.invalidPath
        }

        guard fileManager.fileExists(atPath: path) else {
            throw FileServiceError.fileNotFound
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))

            if let content = String(data: data, encoding: .utf8) {
                return content
            } else {
                throw FileServiceError.writeFailed("File is not a valid UTF-8 text file")
            }
        } catch let error as FileServiceError {
            throw error
        } catch {
            throw FileServiceError.writeFailed(error.localizedDescription)
        }
    }

    /// Checks if file is writable
    /// - Parameter path: Absolute path to the file
    /// - Returns: true if writable
    func isWritable(path: String) async -> Bool {
        fileManager.isWritableFile(atPath: path)
    }

    /// Creates a new file with optional content
    /// - Parameters:
    ///   - path: Absolute path for the new file
    ///   - content: Initial content (default: empty string)
    /// - Throws: FileServiceError if creation fails
    func createFile(at path: String, content: String = "") async throws {
        guard !path.isEmpty else {
            throw FileServiceError.invalidPath
        }

        guard !fileManager.fileExists(atPath: path) else {
            throw FileServiceError.fileAlreadyExists
        }

        do {
            let url = URL(fileURLWithPath: path)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw FileServiceError.createFailed(error.localizedDescription)
        }
    }

    /// Creates a new directory
    /// - Parameter path: Absolute path for the new directory
    /// - Throws: FileServiceError if creation fails
    func createDirectory(at path: String) async throws {
        guard !path.isEmpty else {
            throw FileServiceError.invalidPath
        }

        guard !fileManager.fileExists(atPath: path) else {
            throw FileServiceError.fileAlreadyExists
        }

        do {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: false,
                attributes: nil
            )
        } catch {
            throw FileServiceError.createFailed(error.localizedDescription)
        }
    }

    /// Renames a file or directory
    /// - Parameters:
    ///   - fromPath: Current absolute path
    ///   - toPath: New absolute path
    /// - Throws: FileServiceError if rename fails
    func renameItem(from fromPath: String, to toPath: String) async throws {
        guard !fromPath.isEmpty, !toPath.isEmpty else {
            throw FileServiceError.invalidPath
        }

        guard fileManager.fileExists(atPath: fromPath) else {
            throw FileServiceError.fileNotFound
        }

        guard !fileManager.fileExists(atPath: toPath) else {
            throw FileServiceError.fileAlreadyExists
        }

        do {
            try fileManager.moveItem(atPath: fromPath, toPath: toPath)
        } catch {
            throw FileServiceError.renameFailed(error.localizedDescription)
        }
    }

    /// Deletes a file or directory
    /// - Parameter path: Absolute path to delete
    /// - Throws: FileServiceError if deletion fails
    func deleteItem(at path: String) async throws {
        guard !path.isEmpty else {
            throw FileServiceError.invalidPath
        }

        guard fileManager.fileExists(atPath: path) else {
            throw FileServiceError.fileNotFound
        }

        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw FileServiceError.deleteFailed(error.localizedDescription)
        }
    }

    /// Checks if item exists at path
    /// - Parameter path: Absolute path to check
    /// - Returns: true if item exists
    func itemExists(at path: String) async -> Bool {
        fileManager.fileExists(atPath: path)
    }
}
