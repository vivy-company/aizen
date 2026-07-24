//
//  WorkspaceTreeGeometry.swift
//  aizen
//
//  Pure split-tree -> frame resolution. The renderer hosts panes flat and
//  positions them from these frames, so split mutations never reparent
//  AppKit-backed pane content (Metal terminal surfaces, web views).
//

import CoreGraphics
import Foundation

nonisolated struct WorkspaceTreeGeometry: Equatable {
    struct PaneFrame: Equatable {
        let pane: WorkspacePane
        let frame: CGRect
    }

    struct DividerFrame: Equatable, Hashable {
        let path: SplitPath
        let direction: SplitDirection
        let ratio: Double
        /// Full region of the split this divider belongs to; drag positions
        /// convert to ratios relative to it.
        let region: CGRect
        /// Center of the visible divider line.
        let center: CGPoint

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.path == rhs.path && lhs.direction == rhs.direction
                && lhs.ratio == rhs.ratio && lhs.region == rhs.region && lhs.center == rhs.center
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(path)
        }
    }

    static let dividerVisibleSize: CGFloat = 1
    static let dividerHitSlop: CGFloat = 6
    static let minPaneSize: CGFloat = 10

    private(set) var panes: [PaneFrame] = []
    private(set) var dividers: [DividerFrame] = []

    init(tree: WorkspaceSplitNode, size: CGSize) {
        resolve(tree, in: CGRect(origin: .zero, size: size), path: [])
    }

    /// Converts a drag location to the ratio for the given divider, keeping
    /// both sides at least `minPaneSize`.
    static func ratio(for location: CGPoint, divider: DividerFrame) -> Double {
        switch divider.direction {
        case .horizontal:
            guard divider.region.width > 0 else { return divider.ratio }
            let x = min(max(divider.region.minX + minPaneSize, location.x), divider.region.maxX - minPaneSize)
            return Double((x - divider.region.minX) / divider.region.width)
        case .vertical:
            guard divider.region.height > 0 else { return divider.ratio }
            let y = min(max(divider.region.minY + minPaneSize, location.y), divider.region.maxY - minPaneSize)
            return Double((y - divider.region.minY) / divider.region.height)
        }
    }

    private mutating func resolve(_ node: WorkspaceSplitNode, in rect: CGRect, path: SplitPath) {
        switch node {
        case .leaf(let pane):
            panes.append(PaneFrame(pane: pane, frame: rect))

        case .split(let split):
            var leftRect = rect
            var rightRect = rect
            let center: CGPoint

            switch split.direction {
            case .horizontal:
                // Whole-point pane sizes keep terminal cell grids crisp.
                let leftWidth = max(0, (rect.width * split.ratio - Self.dividerVisibleSize / 2).rounded(.down))
                leftRect.size.width = leftWidth
                rightRect.origin.x = rect.minX + leftWidth + Self.dividerVisibleSize
                rightRect.size.width = max(0, rect.width - leftWidth - Self.dividerVisibleSize)
                center = CGPoint(x: rect.minX + leftWidth + Self.dividerVisibleSize / 2, y: rect.midY)

            case .vertical:
                let topHeight = max(0, (rect.height * split.ratio - Self.dividerVisibleSize / 2).rounded(.down))
                leftRect.size.height = topHeight
                rightRect.origin.y = rect.minY + topHeight + Self.dividerVisibleSize
                rightRect.size.height = max(0, rect.height - topHeight - Self.dividerVisibleSize)
                center = CGPoint(x: rect.midX, y: rect.minY + topHeight + Self.dividerVisibleSize / 2)
            }

            dividers.append(DividerFrame(
                path: path,
                direction: split.direction,
                ratio: split.ratio,
                region: rect,
                center: center
            ))
            resolve(split.left, in: leftRect, path: path + [.left])
            resolve(split.right, in: rightRect, path: path + [.right])
        }
    }
}
