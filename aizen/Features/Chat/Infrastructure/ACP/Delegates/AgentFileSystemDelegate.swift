//
//  AgentFileSystemDelegate.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Foundation

/// Actor responsible for handling file system operations for agent sessions
actor AgentFileSystemDelegate {
    private static let readChunkSize = 64 * 1024


    // MARK: - Initialization

    init() {}

    // MARK: - File Operations

    /// Handle file read request from agent
    /// - Parameters:
    ///   - path: File path to read
    ///   - sessionId: Session identifier (for tracking/logging)
    ///   - line: Starting line number (1-based per ACP spec)
    ///   - limit: Number of lines to read
    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        let url = URL(fileURLWithPath: path)
        let readWindow = FileReadWindow(
            startLine: max(1, line ?? 1),
            limit: limit
        )
        let readResult = try readTextFile(at: url, window: readWindow)

        return ReadTextFileResponse(
            content: readResult.content,
            totalLines: readResult.totalLines,
            _meta: nil
        )
    }

    /// Handle file write request from agent
    /// Per ACP spec: Client MUST create the file if it doesn't exist
    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default

        // Create parent directories if needed (ACP spec requires creating file if it doesn't exist)
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return WriteTextFileResponse(_meta: nil)
        } catch {
            throw error
        }
    }

    // MARK: - Private Helpers

    private func readTextFile(at url: URL, window: FileReadWindow) throws -> FileReadResult {
        if window.isFullFile {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return FileReadResult(
                content: String(decoding: data, as: UTF8.self),
                totalLines: totalLineCount(in: data)
            )
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var leftover = Data()
        var selectedContent = Data()
        var totalLines = 0
        var sawAnyBytes = false
        var lastByteWasNewline = false

        while let chunk = try handle.read(upToCount: Self.readChunkSize), !chunk.isEmpty {
            sawAnyBytes = true
            lastByteWasNewline = chunk.last == 0x0A
            leftover.append(chunk)

            while let newlineIndex = leftover.firstIndex(of: 0x0A) {
                let lineData = leftover.prefix(upTo: newlineIndex)
                totalLines += 1
                appendLineIfNeeded(
                    Data(lineData),
                    lineNumber: totalLines,
                    to: &selectedContent,
                    window: window
                )
                leftover.removeSubrange(...newlineIndex)
            }
        }

        if !leftover.isEmpty {
            totalLines += 1
            appendLineIfNeeded(
                leftover,
                lineNumber: totalLines,
                to: &selectedContent,
                window: window
            )
        } else if !sawAnyBytes || lastByteWasNewline {
            totalLines += 1
            appendLineIfNeeded(
                Data(),
                lineNumber: totalLines,
                to: &selectedContent,
                window: window
            )
        }

        return FileReadResult(
            content: String(decoding: selectedContent, as: UTF8.self),
            totalLines: totalLines
        )
    }

    private func appendLineIfNeeded(
        _ lineData: Data,
        lineNumber: Int,
        to selectedContent: inout Data,
        window: FileReadWindow
    ) {
        guard window.includes(lineNumber: lineNumber) else {
            return
        }

        if !selectedContent.isEmpty {
            selectedContent.append(0x0A)
        }
        selectedContent.append(lineData)
    }

    private func totalLineCount(in data: Data) -> Int {
        guard !data.isEmpty else {
            return 1
        }

        let newlineCount = data.reduce(into: 0) { partialResult, byte in
            if byte == 0x0A {
                partialResult += 1
            }
        }

        if data.last == 0x0A {
            return newlineCount + 1
        }

        return newlineCount + 1
    }
}

private struct FileReadWindow {
    let startLine: Int
    let limit: Int?

    nonisolated var isFullFile: Bool {
        startLine == 1 && limit == nil
    }

    nonisolated func includes(lineNumber: Int) -> Bool {
        guard lineNumber >= startLine else {
            return false
        }

        guard let limit else {
            return true
        }

        guard limit > 0 else {
            return false
        }

        return lineNumber < startLine + limit
    }
}

private struct FileReadResult {
    let content: String
    let totalLines: Int
}
