//
//  aizenTests.swift
//  aizenTests
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Testing
@testable import aizen
import Foundation

struct aizenTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func fileSearchRespectsLimit() async throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory.appendingPathComponent("aizen-filesearch-\(UUID().uuidString)")
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: baseURL) }

        for i in 0..<120 {
            let url = baseURL.appendingPathComponent("file\(i).swift")
            try "print(\(i))\n".write(to: url, atomically: true, encoding: .utf8)
        }

        await FileSearchService.shared.clearAllCaches()

        let indexed = try await FileSearchService.shared.indexDirectory(baseURL.path)
        #expect(indexed.count == 120)

        let limitedEmpty = await FileSearchService.shared.search(
            query: "",
            in: indexed,
            worktreePath: baseURL.path,
            limit: 10
        )
        #expect(limitedEmpty.count == 10)

        let limitedQuery = await FileSearchService.shared.search(
            query: "file1",
            in: indexed,
            worktreePath: baseURL.path,
            limit: 10
        )
        #expect(limitedQuery.count <= 10)
        #expect(!limitedQuery.isEmpty)
    }
}
