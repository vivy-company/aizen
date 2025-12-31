import Foundation

nonisolated enum MergeResult: Equatable, Sendable {
    case success
    case conflict(files: [String])
    case alreadyUpToDate
}
