import Foundation

nonisolated struct ProjectSearchStatus: Equatable, Sendable {
    let scannedFilesCount: Int
    let isScanning: Bool
    let isWatcherReady: Bool
    let isWarmupComplete: Bool

    static let idle = ProjectSearchStatus(
        scannedFilesCount: 0,
        isScanning: false,
        isWatcherReady: false,
        isWarmupComplete: false
    )
}

nonisolated struct ProjectSearchFileResult: Identifiable, Equatable, Sendable {
    let path: String
    let relativePath: String
    let name: String
    let matchScore: Int
    let openRequest: SearchOpenRequest

    var id: String { path }
}

nonisolated struct ProjectSearchContentResult: Identifiable, Equatable, Sendable {
    let path: String
    let relativePath: String
    let name: String
    let lineContent: String
    let lineNumber: Int
    let column: Int
    let contextBefore: [String]
    let contextAfter: [String]
    let isDefinition: Bool
    let openRequest: SearchOpenRequest

    var id: String {
        "\(path):\(lineNumber):\(column)"
    }
}

nonisolated enum ProjectSearchResult: Identifiable, Equatable, Sendable {
    case file(ProjectSearchFileResult)
    case content(ProjectSearchContentResult)

    var id: String {
        switch self {
        case .file(let result):
            return result.id
        case .content(let result):
            return result.id
        }
    }

    var path: String {
        switch self {
        case .file(let result):
            return result.path
        case .content(let result):
            return result.path
        }
    }

    var relativePath: String {
        switch self {
        case .file(let result):
            return result.relativePath
        case .content(let result):
            return result.relativePath
        }
    }

    var name: String {
        switch self {
        case .file(let result):
            return result.name
        case .content(let result):
            return result.name
        }
    }

    var openRequest: SearchOpenRequest {
        switch self {
        case .file(let result):
            return result.openRequest
        case .content(let result):
            return result.openRequest
        }
    }
}

nonisolated struct ProjectFileSearchResponse: Equatable, Sendable {
    let results: [ProjectSearchFileResult]
    let totalMatched: Int
    let totalFiles: Int
    let status: ProjectSearchStatus
}

nonisolated struct ProjectContentSearchResponse: Equatable, Sendable {
    let results: [ProjectSearchContentResult]
    let totalMatched: Int
    let totalFiles: Int
    let nextFileOffset: Int?
    let regexFallbackError: String?
    let status: ProjectSearchStatus
}
