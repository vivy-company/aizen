import Foundation

nonisolated struct ProjectSearchPreview: Equatable, Sendable {
    let path: String
    let relativePath: String
    let content: String
    let openRequest: SearchOpenRequest?
}

nonisolated enum ProjectSearchPreviewState: Equatable, Sendable {
    case idle(String)
    case loading
    case loaded(ProjectSearchPreview)
    case unavailable(String)
}
