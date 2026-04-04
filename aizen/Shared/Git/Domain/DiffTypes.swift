import Foundation

// MARK: - Diff Line Type

nonisolated enum DiffLineType: String, Hashable, Codable, Sendable {
    case added
    case deleted
    case context
    case header

    var marker: String {
        switch self {
        case .added: return "+"
        case .deleted: return "-"
        case .context: return " "
        case .header: return ""
        }
    }
}

// MARK: - Diff Line

nonisolated struct DiffLine: Identifiable, Hashable, Sendable {
    let lineNumber: Int
    let oldLineNumber: String?
    let newLineNumber: String?
    let content: String
    let type: DiffLineType

    var id: Int { lineNumber }

    func hash(into hasher: inout Hasher) {
        hasher.combine(lineNumber)
        hasher.combine(content)
        hasher.combine(type)
    }

    static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
        lhs.lineNumber == rhs.lineNumber &&
        lhs.content == rhs.content &&
        lhs.type == rhs.type
    }
}
