import CoreGraphics
import Foundation
import Testing
@testable import Aizen

struct WorkspaceSplitTreeTests {

    private func pane(_ id: String, kind: PaneKind = .terminal) -> WorkspacePane {
        WorkspacePane(id: id, kind: kind)
    }

    // MARK: - Codec

    @Test func decodesLegacyTerminalLayout() throws {
        let legacyJSON = """
        {
          "type": "split",
          "direction": "horizontal",
          "ratio": 0.6,
          "left": { "type": "leaf", "paneId": "pane-a" },
          "right": { "type": "leaf", "paneId": "pane-b" }
        }
        """

        let tree = try #require(WorkspaceLayoutCodec.decode(legacyJSON))
        #expect(tree.allPaneIds() == ["pane-a", "pane-b"])
        #expect(tree.allPanes().allSatisfy { $0.kind == .terminal })

        guard case .split(let split) = tree else {
            Issue.record("Expected split root")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(split.ratio == 0.6)
    }

    @Test func roundTripsCurrentFormat() throws {
        let tree = WorkspaceSplitNode.split(.init(
            direction: .vertical,
            ratio: 0.4,
            left: .leaf(pane("a", kind: .chat)),
            right: .leaf(pane("b", kind: .browser))
        ))

        let json = try #require(WorkspaceLayoutCodec.encode(tree))
        let decoded = try #require(WorkspaceLayoutCodec.decode(json))
        #expect(decoded == tree)
        #expect(decoded.pane(withId: "a")?.kind == .chat)
        #expect(decoded.pane(withId: "b")?.kind == .browser)
    }

    // MARK: - Mutations

    @Test func splittingInsertsAfterAndBefore() {
        let root = WorkspaceSplitNode.leaf(pane("a"))

        let after = root.splitting(
            paneId: "a", direction: .horizontal, insertion: .after,
            newPane: pane("b")
        )
        #expect(after.allPaneIds() == ["a", "b"])

        let before = root.splitting(
            paneId: "a", direction: .vertical, insertion: .before,
            newPane: pane("c")
        )
        #expect(before.allPaneIds() == ["c", "a"])
    }

    @Test func splittingMissingPaneReturnsUnchangedTree() {
        let root = WorkspaceSplitNode.leaf(pane("a"))
        let result = root.splitting(
            paneId: "missing", direction: .horizontal, insertion: .after,
            newPane: pane("b")
        )
        #expect(result == root)
    }

    @Test func updatingPaneReplacesKindInPlace() {
        let sessionId = UUID()
        let tree = WorkspaceSplitNode.split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(pane("a")),
            right: .leaf(pane("b"))
        ))

        let updated = tree.updatingPane("b") { p in
            p.kind = .browser
            p.sessionId = sessionId
        }

        #expect(updated.pane(withId: "b")?.kind == .browser)
        #expect(updated.pane(withId: "b")?.sessionId == sessionId)
        #expect(updated.pane(withId: "a")?.kind == .terminal)
        #expect(updated.allPaneIds() == ["a", "b"])
    }

    @Test func removingPanePromotesSibling() {
        let tree = WorkspaceSplitNode.split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(pane("a")),
            right: .split(.init(
                direction: .vertical,
                ratio: 0.5,
                left: .leaf(pane("b")),
                right: .leaf(pane("c"))
            ))
        ))

        let removed = tree.removingPane("b")
        #expect(removed?.allPaneIds() == ["a", "c"])

        let lastRemoved = WorkspaceSplitNode.leaf(pane("a")).removingPane("a")
        #expect(lastRemoved == nil)
    }

    @Test func equalizedUsesDirectionWeights() {
        // (a | b) | c in the same direction: a and b each weigh 1, so the root
        // split gives 2/3 to its left subtree.
        let tree = WorkspaceSplitNode.split(.init(
            direction: .horizontal,
            ratio: 0.9,
            left: .split(.init(
                direction: .horizontal,
                ratio: 0.2,
                left: .leaf(pane("a")),
                right: .leaf(pane("b"))
            )),
            right: .leaf(pane("c"))
        ))

        let equalized = tree.equalized()
        guard case .split(let root) = equalized,
              case .split(let inner) = root.left else {
            Issue.record("Unexpected tree shape")
            return
        }
        #expect(abs(root.ratio - 2.0 / 3.0) < 0.001)
        #expect(abs(inner.ratio - 0.5) < 0.001)
    }

    @Test func updatingRatioByPathClampsAndTargetsCorrectSplit() {
        let tree = WorkspaceSplitNode.split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(pane("a")),
            right: .split(.init(
                direction: .vertical,
                ratio: 0.5,
                left: .leaf(pane("b")),
                right: .leaf(pane("c"))
            ))
        ))

        let updated = tree.updatingRatio(at: [.right], to: 0.99)
        guard case .split(let root) = updated,
              case .split(let inner) = root.right else {
            Issue.record("Unexpected tree shape")
            return
        }
        #expect(root.ratio == 0.5)
        #expect(inner.ratio == 0.9)

        let rootUpdated = tree.updatingRatio(at: [], to: 0.3)
        guard case .split(let newRoot) = rootUpdated else {
            Issue.record("Unexpected tree shape")
            return
        }
        #expect(newRoot.ratio == 0.3)
    }

    @Test func nodeAtPathResolves() {
        let inner = WorkspaceSplitNode.split(.init(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(pane("b")),
            right: .leaf(pane("c"))
        ))
        let tree = WorkspaceSplitNode.split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(pane("a")),
            right: inner
        ))

        #expect(tree.node(at: []) == tree)
        #expect(tree.node(at: [.left]) == .leaf(pane("a")))
        #expect(tree.node(at: [.right]) == inner)
        #expect(tree.node(at: [.right, .left]) == .leaf(pane("b")))
        #expect(tree.node(at: [.left, .left]) == nil)
    }

    // MARK: - Geometry

    @Test func geometryTilesWithoutOverlap() {
        let tree = WorkspaceSplitNode.split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(pane("a")),
            right: .split(.init(
                direction: .vertical,
                ratio: 0.5,
                left: .leaf(pane("b")),
                right: .leaf(pane("c"))
            ))
        ))

        let geometry = WorkspaceTreeGeometry(tree: tree, size: CGSize(width: 200, height: 100))
        #expect(geometry.panes.count == 3)
        #expect(geometry.dividers.count == 2)

        let frames = Dictionary(uniqueKeysWithValues: geometry.panes.map { ($0.pane.id, $0.frame) })
        let a = frames["a"]!
        let b = frames["b"]!
        let c = frames["c"]!

        #expect(a.minX == 0)
        #expect(a.height == 100)
        #expect(b.minX == c.minX)
        #expect(b.minX > a.maxX)
        #expect(c.minY > b.maxY)
        #expect(abs(c.maxY - 100) < 0.001)
        #expect(abs(b.maxX - 200) < 0.001)

        // Divider paths address the splits they belong to.
        #expect(geometry.dividers.map(\.path) == [[], [.right]])
    }

    @Test func geometryDragRatioRespectsMinPaneSize() {
        let tree = WorkspaceSplitNode.split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(pane("a")),
            right: .leaf(pane("b"))
        ))
        let geometry = WorkspaceTreeGeometry(tree: tree, size: CGSize(width: 100, height: 100))
        let divider = geometry.dividers[0]

        let clampedLow = WorkspaceTreeGeometry.ratio(for: CGPoint(x: 0, y: 50), divider: divider)
        let clampedHigh = WorkspaceTreeGeometry.ratio(for: CGPoint(x: 100, y: 50), divider: divider)
        let mid = WorkspaceTreeGeometry.ratio(for: CGPoint(x: 50, y: 50), divider: divider)

        #expect(abs(clampedLow - 0.1) < 0.001)
        #expect(abs(clampedHigh - 0.9) < 0.001)
        #expect(abs(mid - 0.5) < 0.001)
    }
}
