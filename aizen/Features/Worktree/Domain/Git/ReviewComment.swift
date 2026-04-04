//
//  ReviewComment.swift
//  aizen
//
//  Data models for diff review comments
//

import Foundation
import CryptoKit

// MARK: - Review Comment

struct ReviewComment: Codable, Identifiable, Hashable {
    let id: UUID
    let filePath: String
    let lineNumber: Int
    let oldLineNumber: String?
    let newLineNumber: String?
    let lineType: DiffLineType
    let codeContext: String
    let codeContextHash: String
    var comment: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        filePath: String,
        lineNumber: Int,
        oldLineNumber: String?,
        newLineNumber: String?,
        lineType: DiffLineType,
        codeContext: String,
        comment: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.lineType = lineType
        self.codeContext = codeContext
        self.codeContextHash = Self.hash(codeContext)
        self.comment = comment
        self.createdAt = createdAt
    }

    static func hash(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    var displayLineNumber: String {
        newLineNumber ?? oldLineNumber ?? "\(lineNumber)"
    }
}

// MARK: - Review Session

struct ReviewSession: Codable {
    let repositoryPath: String
    var comments: [ReviewComment]
    let createdAt: Date
    var updatedAt: Date

    init(repositoryPath: String, comments: [ReviewComment] = []) {
        self.repositoryPath = repositoryPath
        self.comments = comments
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
