//
//  GitCommit.swift
//  aizen
//
//  Data model for git commit history
//

import Foundation

struct GitCommit: Identifiable, Equatable {
    let id: String  // full commit hash
    let shortHash: String
    let message: String
    let author: String
    let date: Date
    let filesChanged: Int
    let additions: Int
    let deletions: Int

    var relativeDate: String {
        RelativeDateFormatter.shared.string(from: date)
    }
}
