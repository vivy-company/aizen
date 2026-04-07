import Foundation

extension SplitNode {
    /// A hashable representation of the tree structure that intentionally ignores split ratios.
    ///
    /// Ghostty uses explicit structural identity for split trees because SwiftUI's implicit
    /// identity is unreliable for recursive terminal layouts when nodes are inserted or removed.
    var structuralIdentity: StructuralIdentity {
        StructuralIdentity(self)
    }

    struct StructuralIdentity: Hashable {
        private let node: SplitNode

        init(_ node: SplitNode) {
            self.node = node
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.node.isStructurallyEqual(to: rhs.node)
        }

        func hash(into hasher: inout Hasher) {
            node.hashStructure(into: &hasher)
        }
    }

    func isStructurallyEqual(to other: SplitNode) -> Bool {
        switch (self, other) {
        case let (.leaf(lhsPaneId), .leaf(rhsPaneId)):
            return lhsPaneId == rhsPaneId
        case let (.split(lhsSplit), .split(rhsSplit)):
            return lhsSplit.direction == rhsSplit.direction &&
                lhsSplit.left.isStructurallyEqual(to: rhsSplit.left) &&
                lhsSplit.right.isStructurallyEqual(to: rhsSplit.right)
        default:
            return false
        }
    }

    func hashStructure(into hasher: inout Hasher) {
        switch self {
        case .leaf(let paneId):
            hasher.combine(HashKey.leaf)
            hasher.combine(paneId)
        case .split(let split):
            hasher.combine(HashKey.split)
            hasher.combine(split.direction)
            split.left.hashStructure(into: &hasher)
            split.right.hashStructure(into: &hasher)
        }
    }

    private enum HashKey: UInt8 {
        case leaf = 0
        case split = 1
    }
}

enum TerminalLayoutDefaults {
    static func paneId(sessionId: UUID?, focusedPaneId: String?) -> String {
        if let focusedPaneId {
            let trimmed = focusedPaneId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let sessionId {
            return sessionId.uuidString
        }

        return UUID().uuidString
    }

    static func defaultLayout(paneId: String) -> SplitNode {
        .leaf(paneId: paneId)
    }
}

struct SplitLayoutHelper {
    static func encode(_ node: SplitNode) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(node),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func decode(_ json: String) -> SplitNode? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(SplitNode.self, from: data)
    }

    static func createDefault(paneId: String = UUID().uuidString) -> SplitNode {
        TerminalLayoutDefaults.defaultLayout(paneId: paneId)
    }
}
