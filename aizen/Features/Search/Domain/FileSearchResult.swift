//
//  FileSearchResult.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation

struct FileSearchResult: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let path: String
    let relativePath: String
    let isDirectory: Bool
    var matchScore: Double

    init(path: String, relativePath: String, isDirectory: Bool, matchScore: Double = 0) {
        self.id = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.path = path
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.matchScore = matchScore
    }
}
