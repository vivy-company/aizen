//
//  TerminalSplitLayout.swift
//  aizen
//
//  Split pane layout based on Ghostty's SplitTree implementation
//

import Foundation

// MARK: - Split Direction

enum SplitDirection: String, Codable {
    case horizontal  // left | right
    case vertical    // top / bottom
}

// MARK: - Split Node

indirect enum SplitNode: Codable, Equatable {
    case leaf(paneId: String)
    case split(Split)

    struct Split: Codable, Equatable {
        let direction: SplitDirection
        let ratio: Double  // 0.0 to 1.0, left/top percentage
        let left: SplitNode  // Left (horizontal) or top (vertical)
        let right: SplitNode  // Right (horizontal) or bottom (vertical)
    }

    // Legacy support for old hsplit/vsplit format
    private enum LegacyNode: String, Codable {
        case leaf, hsplit, vsplit
    }

    enum CodingKeys: String, CodingKey {
        case type, paneId, direction, ratio, left, right
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "leaf":
            let id = try container.decode(String.self, forKey: .paneId)
            self = .leaf(paneId: id)
        case "split":
            let direction = try container.decode(SplitDirection.self, forKey: .direction)
            let ratio = try container.decode(Double.self, forKey: .ratio)
            let left = try container.decode(SplitNode.self, forKey: .left)
            let right = try container.decode(SplitNode.self, forKey: .right)
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
        case .leaf(let paneId):
            try container.encode("leaf", forKey: .type)
            try container.encode(paneId, forKey: .paneId)
        case .split(let split):
            try container.encode("split", forKey: .type)
            try container.encode(split.direction, forKey: .direction)
            try container.encode(split.ratio, forKey: .ratio)
            try container.encode(split.left, forKey: .left)
            try container.encode(split.right, forKey: .right)
        }
    }

    // MARK: - Tree Operations

    func allPaneIds() -> [String] {
        switch self {
        case .leaf(let paneId):
            return [paneId]
        case .split(let split):
            return split.left.allPaneIds() + split.right.allPaneIds()
        }
    }

    func leafCount() -> Int {
        switch self {
        case .leaf:
            return 1
        case .split(let split):
            return split.left.leafCount() + split.right.leafCount()
        }
    }

    // MARK: - Ghostty Equalization Algorithm

    /// Calculate weight for direction-aware equalization
    /// Same-direction splits contribute their child weights
    /// Cross-direction splits count as single unit
    private func weight(for direction: SplitDirection) -> Int {
        switch self {
        case .leaf:
            return 1
        case .split(let split):
            if split.direction == direction {
                // Same direction: weights add
                return split.left.weight(for: direction) + split.right.weight(for: direction)
            } else {
                // Cross direction: single unit
                return 1
            }
        }
    }

    /// Equalize split ratios based on Ghostty's weight algorithm
    func equalized() -> SplitNode {
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
                ratio: max(0.1, min(0.9, newRatio)),  // Clamp 10%-90%
                left: split.left.equalized(),
                right: split.right.equalized()
            ))
        }
    }

    func replacingPane(_ targetId: String, with newNode: SplitNode) -> SplitNode {
        switch self {
        case .leaf(let paneId):
            return paneId == targetId ? newNode : self
        case .split(let split):
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.replacingPane(targetId, with: newNode),
                right: split.right.replacingPane(targetId, with: newNode)
            ))
        }
    }

    func removingPane(_ targetId: String) -> SplitNode? {
        switch self {
        case .leaf(let paneId):
            return paneId == targetId ? nil : self
        case .split(let split):
            let newLeft = split.left.removingPane(targetId)
            let newRight = split.right.removingPane(targetId)

            // If left removed, promote right
            if newLeft == nil {
                return newRight
            }
            // If right removed, promote left
            if newRight == nil {
                return newLeft
            }
            // Both remain, preserve split with same ratio
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: newLeft!,
                right: newRight!
            ))
        }
    }

    // Update THIS split's ratio (used when the split itself is being resized)
    func withUpdatedRatio(_ newRatio: Double) -> SplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let split):
            return .split(Split(
                direction: split.direction,
                ratio: max(0.1, min(0.9, newRatio)),
                left: split.left,
                right: split.right
            ))
        }
    }

    // Replace a specific node in the tree (by structural equality)
    func replacingNode(_ oldNode: SplitNode, with newNode: SplitNode) -> SplitNode {
        // If this is the node to replace, return the new node
        if self == oldNode {
            return newNode
        }

        // Recurse into children
        switch self {
        case .leaf:
            return self
        case .split(let split):
            return .split(Split(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.replacingNode(oldNode, with: newNode),
                right: split.right.replacingNode(oldNode, with: newNode)
            ))
        }
    }

    private func containsPane(_ paneId: String) -> Bool {
        return allPaneIds().contains(paneId)
    }
}

// Helper for encoding/decoding layout to JSON
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

    static func createDefault() -> SplitNode {
        return .leaf(paneId: UUID().uuidString)
    }
}
