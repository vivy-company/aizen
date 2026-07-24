//
//  WorkspaceSplitTreeView.swift
//  aizen
//
//  Flat renderer for a workspace split tree. Leaves are hosted once, keyed by
//  pane id, and repositioned by frame when the tree changes — splitting,
//  resizing, and closing never reparent leaf content.
//

import SwiftUI

struct WorkspaceSplitTreeView<Leaf: View>: View {
    let tree: WorkspaceSplitNode
    let dividerColor: Color
    let onResize: (SplitPath, Double) -> Void
    let onEqualize: () -> Void
    @ViewBuilder let leaf: (WorkspacePane) -> Leaf

    private static var treeSpace: String { "workspaceSplitTree" }

    var body: some View {
        GeometryReader { proxy in
            let geometry = WorkspaceTreeGeometry(tree: tree, size: proxy.size)

            ZStack(alignment: .topLeading) {
                PaneFrameLayout(frames: Dictionary(
                    uniqueKeysWithValues: geometry.panes.map { ($0.pane.id, $0.frame) }
                )) {
                    ForEach(geometry.panes, id: \.pane.id) { paneFrame in
                        leaf(paneFrame.pane)
                            .layoutValue(key: PaneIdLayoutKey.self, value: paneFrame.pane.id)
                    }
                }

                ForEach(geometry.dividers, id: \.path) { divider in
                    WorkspaceDividerView(direction: divider.direction, color: dividerColor)
                        .frame(
                            width: divider.direction == .vertical ? divider.region.width : nil,
                            height: divider.direction == .horizontal ? divider.region.height : nil
                        )
                        .position(divider.center)
                        .gesture(
                            DragGesture(coordinateSpace: .named(Self.treeSpace))
                                .onChanged { gesture in
                                    onResize(
                                        divider.path,
                                        WorkspaceTreeGeometry.ratio(for: gesture.location, divider: divider)
                                    )
                                }
                        )
                        .onTapGesture(count: 2) {
                            onEqualize()
                        }
                }
            }
            .coordinateSpace(name: Self.treeSpace)
        }
    }
}

// MARK: - Pane Layout

/// Places each pane subview at its resolved frame. A real `Layout` (not a
/// visual transform) so AppKit-backed content gets correct frames for
/// hit-testing.
private struct PaneFrameLayout: Layout {
    let frames: [String: CGRect]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            guard let frame = frames[subview[PaneIdLayoutKey.self]] else {
                subview.place(at: bounds.origin, proposal: .zero)
                continue
            }
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

nonisolated private struct PaneIdLayoutKey: LayoutValueKey {
    static let defaultValue: String = ""
}

// MARK: - Divider

struct WorkspaceDividerView: View {
    let direction: SplitDirection
    let color: Color

    private var visibleSize: CGFloat { WorkspaceTreeGeometry.dividerVisibleSize }
    private var hitSize: CGFloat {
        WorkspaceTreeGeometry.dividerVisibleSize + WorkspaceTreeGeometry.dividerHitSlop
    }

    var body: some View {
        pointerStyled(
            ZStack {
                Color.clear
                    .frame(
                        width: direction == .horizontal ? hitSize : nil,
                        height: direction == .vertical ? hitSize : nil
                    )
                    .contentShape(Rectangle())
                Rectangle()
                    .fill(color)
                    .frame(
                        width: direction == .horizontal ? visibleSize : nil,
                        height: direction == .vertical ? visibleSize : nil
                    )
            }
        )
    }

    @ViewBuilder
    private func pointerStyled<Content: View>(_ content: Content) -> some View {
        if #available(macOS 15.0, *) {
            switch direction {
            case .horizontal:
                content.pointerStyle(.frameResize(position: .trailing))
            case .vertical:
                content.pointerStyle(.frameResize(position: .top))
            }
        } else {
            content.onHover { isHovered in
                if isHovered {
                    switch direction {
                    case .horizontal:
                        NSCursor.resizeLeftRight.push()
                    case .vertical:
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}
