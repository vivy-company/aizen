//
//  ReviewSessionStore.swift
//  aizen
//
//  Stores review comments persistence and export state.
//

import Foundation
import CryptoKit
import Combine

@MainActor
final class ReviewSessionStore: ObservableObject {
    @Published var comments: [ReviewComment] = []
    @Published var isLoaded = false

    private var repositoryPath: String = ""
    private let fileManager = FileManager.default

    private var reviewsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Aizen/reviews", isDirectory: true)
    }

    private func sessionFilePath(for repoPath: String) -> URL {
        let hash = SHA256.hash(data: Data(repoPath.utf8))
        let hashString = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return reviewsDirectory.appendingPathComponent("\(hashString).json")
    }

    // MARK: - Load/Save

    func load(for repoPath: String) {
        repositoryPath = repoPath

        let filePath = sessionFilePath(for: repoPath)
        guard fileManager.fileExists(atPath: filePath.path) else {
            comments = []
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let session = try decoder.decode(ReviewSession.self, from: data)
            comments = session.comments
        } catch {
            print("Failed to load review session: \(error)")
            comments = []
        }
        isLoaded = true
    }

    func save() {
        guard !repositoryPath.isEmpty else { return }

        let session = ReviewSession(repositoryPath: repositoryPath, comments: comments)
        let filePath = sessionFilePath(for: repositoryPath)

        do {
            try fileManager.createDirectory(at: reviewsDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(session)
            try data.write(to: filePath)
        } catch {
            print("Failed to save review session: \(error)")
        }
    }

    // MARK: - CRUD

    func addComment(for line: DiffLine, filePath: String, comment: String) {
        let reviewComment = ReviewComment(
            filePath: filePath,
            lineNumber: line.lineNumber,
            oldLineNumber: line.oldLineNumber,
            newLineNumber: line.newLineNumber,
            lineType: line.type,
            codeContext: line.content,
            comment: comment
        )
        comments.append(reviewComment)
        save()
    }

    func updateComment(id: UUID, comment: String) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        comments[index].comment = comment
        save()
    }

    func deleteComment(id: UUID) {
        comments.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        comments.removeAll()
        save()
    }

    // MARK: - Validation

    func validateComments(against diffLines: [String: [DiffLine]]) {
        var validComments: [ReviewComment] = []

        for comment in comments {
            guard let fileLines = diffLines[comment.filePath] else { continue }

            // Find matching line by line number
            let matchingLine = fileLines.first { line in
                if let newNum = comment.newLineNumber, let lineNewNum = line.newLineNumber {
                    return newNum == lineNewNum
                }
                if let oldNum = comment.oldLineNumber, let lineOldNum = line.oldLineNumber {
                    return oldNum == lineOldNum
                }
                return false
            }

            guard let line = matchingLine else { continue }

            // Verify content hasn't changed
            let currentHash = ReviewComment.hash(line.content)
            if currentHash == comment.codeContextHash {
                validComments.append(comment)
            }
        }

        if validComments.count != comments.count {
            comments = validComments
            save()
        }
    }

    // MARK: - Export

    func exportToMarkdown() -> String {
        guard !comments.isEmpty else { return "" }

        var output = ""
        let groupedByFile = Dictionary(grouping: comments) { $0.filePath }

        for (file, fileComments) in groupedByFile.sorted(by: { $0.key < $1.key }) {
            output += "## \(file)\n\n"

            let sortedComments = fileComments.sorted { c1, c2 in
                let num1 = Int(c1.newLineNumber ?? c1.oldLineNumber ?? "0") ?? 0
                let num2 = Int(c2.newLineNumber ?? c2.oldLineNumber ?? "0") ?? 0
                return num1 < num2
            }

            for comment in sortedComments {
                output += "### Line \(comment.displayLineNumber)\n"
                output += "```\n\(comment.codeContext)\n```\n"
                output += "**Comment:** \(comment.comment)\n\n---\n\n"
            }
        }

        return output
    }

    // MARK: - Helpers

    func hasComment(for filePath: String, lineNumber: Int) -> Bool {
        comments.contains { $0.filePath == filePath && $0.lineNumber == lineNumber }
    }

    func commentKey(for filePath: String, lineNumber: Int) -> String {
        "\(filePath):\(lineNumber)"
    }

    var commentedLineKeys: Set<String> {
        Set(comments.map { commentKey(for: $0.filePath, lineNumber: $0.lineNumber) })
    }

    var commentsByFile: [String: [ReviewComment]] {
        Dictionary(grouping: comments) { $0.filePath }
    }
}
