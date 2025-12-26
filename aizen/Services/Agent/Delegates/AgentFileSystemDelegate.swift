//
//  AgentFileSystemDelegate.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import os.log

/// Actor responsible for handling file system operations for agent sessions
actor AgentFileSystemDelegate {

    private let logger = Logger.forCategory("FileSystemDelegate")

    // MARK: - Initialization

    init() {}

    // MARK: - File Operations

    /// Handle file read request from agent
    /// - Parameters:
    ///   - path: File path to read
    ///   - sessionId: Session identifier (for tracking/logging)
    ///   - line: Starting line number (0-indexed position)
    ///   - limit: Number of lines to read
    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let filteredContent: String
        if let startLine = line, let lineLimit = limit {
            let startIdx = max(0, startLine)
            let endIdx = min(lines.count, startLine + lineLimit)
            filteredContent = lines[startIdx..<endIdx].joined(separator: "\n")
        } else if let startLine = line {
            let startIdx = max(0, startLine)
            filteredContent = lines[startIdx...].joined(separator: "\n")
        } else {
            filteredContent = content
        }

        return ReadTextFileResponse(content: filteredContent, totalLines: lines.count, _meta: nil)
    }

    /// Handle file write request from agent
    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        logger.info("Write request for: \(path) (\(content.count) chars)")
        let url = URL(fileURLWithPath: path)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Write succeeded: \(path)")
            return WriteTextFileResponse(_meta: nil)
        } catch {
            logger.error("Write failed for \(path): \(error.localizedDescription)")
            throw error
        }
    }
}
