import Foundation

nonisolated struct SearchOpenRequest: Equatable, Hashable, Sendable {
    let path: String
    let line: Int?
    let column: Int?
    let endLine: Int?
    let endColumn: Int?

    init(
        path: String,
        line: Int? = nil,
        column: Int? = nil,
        endLine: Int? = nil,
        endColumn: Int? = nil
    ) {
        self.path = path
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }

    var hasLocation: Bool {
        line != nil || column != nil || endLine != nil || endColumn != nil
    }
}
