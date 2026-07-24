//
//  WorkspaceSplitTree.swift
//  aizen
//
//  Binary split tree for the workspace working area, derived from Ghostty's
//  SplitTree. Leaves are typed panes; the tree itself is content-agnostic.
//

import Foundation

// MARK: - Split Direction

nonisolated enum SplitDirection: String, Codable {
    case horizontal  // left | right
    case vertical    // top / bottom
}

// MARK: - Split Path

/// Identifies a node by its route from the root. Used to address a specific
/// split (e.g. for ratio updates) without relying on structural equality,
/// which is ambiguous when identical subtrees exist.
nonisolated enum SplitBranch: String, Codable, Hashable {
    case left
    case right
}

typealias SplitPath = [SplitBranch]

// MARK: - Split Node

nonisolated indirect enum WorkspaceSplitNode: Codable, Equatable {
    case leaf(WorkspacePane)
    case split(Split)

    struct Split: Codable, Equatable {
        let direction: SplitDirection
        let ratio: Double  // 0.0 to 1.0, left/top fraction
        let left: WorkspaceSplitNode
        let right: WorkspaceSplitNode
    }

    enum CodingKeys: String, CodingKey {
        case type, pane, paneId, direction, ratio, left, right
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "leaf":
            if let pane = try container.decodeIfPresent(WorkspacePane.self, forKey: .pane) {
                self = .leaf(pane)
            } else {
                // Legacy terminal layout: leaves were bare pane-id strings.
                // Pane ids must survive as-is (tmux sessions and surface caches key on them).
                let id = try container.decode(String.self, forKey: .paneId)
                self = .leaf(WorkspacePane(id: id, kind: .terminal))
            }
        case "split":
            let direction = try container.decode(SplitDirection.self, forKey: .direction)
            let ratio = Self.clampRatio(try container.decode(Double.self, forKey: .ratio))
            let left = try container.decode(WorkspaceSplitNode.self, forKey: .left)
            let right = try container.decode(WorkspaceSplitNode.self, forKey: .right)
            self = .split(Split(direction: direction, ratio: ratio, left: left, right: right))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid split type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .leaf(let pane):
            try container.encode("leaf", forKey: .type)
            try container.encode(pane, forKey: .pane)
        case .split(let split):
            try container.encode("split", forKey: .type)
            try container.encode(split.direction, forKey: .direction)
            try container.encode(split.ratio, forKey: .ratio)
            try container.encode(split.left, forKey: .left)
            try container.encode(split.right, forKey: .right)
        }
    }

    // MARK: - Queries

    /// Panes in left-to-right, top-to-bottom (depth-first) order.
    func allPanes() -> [WorkspacePane] {
        switch self {
        case .leaf(let pane):
            return [pane]
        case .split(let split):
            return split.left.allPanes() + split.right.allPanes()
        }
    }

    func allPaneIds() -> [String] {
        allPanes().map(\.id)
    }

    func pane(withId id: String) -> WorkspacePane? {
        allPanes().first { $0.id == id }
    }

    func leafCount() -> Int {
        switch self {
        case .leaf:
            return 1
        case .split(let split):
            return split.left.leafCount() + split.right.leafCount()
        }
    }

    func node(at path: SplitPath) -> WorkspaceSplitNode? {
        guard let branch = path.first else { return self }
        guard case .split(let split) = self else { return nil }
        let child = branch == .left ? split.left : split.right
        return child.node(at: Array(path.dropFirst()))
    }

    // MARK: - Ghostty Equalization Algorithm

    /// Same-direction splits contribute their child weights; cross-direction
    /// splits count as a single unit.
    private func weight(for direction: SplitDirection) -> Int {
        switch self {
        case .leaf:
            return 1
        case .split(let split):
            if split.direction == direction {
                return split.left.weight(for: direction) + split.right.weight(for: direction)
            } else {
                return 1
            }
        }
    }

    func equalized() -> WorkspaceSplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let split):
            let leftWeight = split.left.weight(for: split.direction)
            let rightWeight = split.right.weight(for: split.direction)
            let totalWeight = leftWeight + rightWeight
            let newRatio = Double(leftWeight) / Double(totalWeight)

            return .split(Split(
                direction: split.direction,
                ratio: Self.clampRatio(newRatio),
                left: split.left.equalized(),
                right: split.right.equalized()
            ))
        }
    }

    // MARK: - Mutations (pure)

    func replacingPane(_ targetId: String, with newNode: WorkspaceSplitNode) -> WorkspaceSplitNode {
        switch self {
        case .leaf(let pane):
            return pane.id == targetId ? newNode : self
        case .split(let split):
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.replacingPane(targetId, with: newNode),
                right: split.right.replacingPane(targetId, with: newNode)
            ))
        }
    }

    /// Removes a pane; the sibling subtree is promoted in its place.
    /// Returns nil when the last pane is removed.
    func removingPane(_ targetId: String) -> WorkspaceSplitNode? {
        switch self {
        case .leaf(let pane):
            return pane.id == targetId ? nil : self
        case .split(let split):
            let newLeft = split.left.removingPane(targetId)
            let newRight = split.right.removingPane(targetId)

            if newLeft == nil {
                return newRight
            }
            if newRight == nil {
                return newLeft
            }
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: newLeft!,
                right: newRight!
            ))
        }
    }

    /// Transforms the pane with the given id in place, preserving its position
    /// in the tree. Used for replacing a pane's kind/session binding.
    func updatingPane(_ targetId: String, _ transform: (inout WorkspacePane) -> Void) -> WorkspaceSplitNode {
        switch self {
        case .leaf(var pane):
            guard pane.id == targetId else { return self }
            transform(&pane)
            return .leaf(pane)
        case .split(let split):
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.updatingPane(targetId, transform),
                right: split.right.updatingPane(targetId, transform)
            ))
        }
    }

    enum SplitInsertion {
        case before  // new pane becomes left/top
        case after   // new pane becomes right/bottom
    }

    /// Splits the target pane, placing `newPane` beside it at a 50/50 ratio.
    /// Returns self unchanged when the target does not exist.
    func splitting(
        paneId targetId: String,
        direction: SplitDirection,
        insertion: SplitInsertion,
        newPane: WorkspacePane
    ) -> WorkspaceSplitNode {
        guard let source = pane(withId: targetId) else { return self }

        let sourceLeaf = WorkspaceSplitNode.leaf(source)
        let newLeaf = WorkspaceSplitNode.leaf(newPane)
        let split: Split
        switch insertion {
        case .before:
            split = Split(direction: direction, ratio: 0.5, left: newLeaf, right: sourceLeaf)
        case .after:
            split = Split(direction: direction, ratio: 0.5, left: sourceLeaf, right: newLeaf)
        }
        return replacingPane(targetId, with: .split(split))
    }

    /// Updates the ratio of the split at `path`. Returns self unchanged when
    /// the path does not resolve to a split.
    func updatingRatio(at path: SplitPath, to newRatio: Double) -> WorkspaceSplitNode {
        guard case .split(let split) = self else { return self }

        guard let branch = path.first else {
            return .split(Split(
                direction: split.direction,
                ratio: Self.clampRatio(newRatio),
                left: split.left,
                right: split.right
            ))
        }

        let remainder = Array(path.dropFirst())
        switch branch {
        case .left:
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.updatingRatio(at: remainder, to: newRatio),
                right: split.right
            ))
        case .right:
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left,
                right: split.right.updatingRatio(at: remainder, to: newRatio)
            ))
        }
    }

    static func clampRatio(_ ratio: Double) -> Double {
        max(0.1, min(0.9, ratio))
    }
}

// MARK: - Codec

/// JSON persistence for split trees. Decoding accepts both the current format
/// and the legacy terminal-only format (bare `paneId` leaves).
nonisolated enum WorkspaceLayoutCodec {
    static func encode(_ node: WorkspaceSplitNode) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(node),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func decode(_ json: String) -> WorkspaceSplitNode? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkspaceSplitNode.self, from: data)
    }
}
