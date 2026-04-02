//
//  GitRepositoryState.swift
//  aizen
//
//  Shared repository availability state for Git UI surfaces.
//

import Foundation

enum GitRepositoryState: Equatable {
    case unknown
    case ready
    case notRepository
    case missingPath
    case error(String)
}
