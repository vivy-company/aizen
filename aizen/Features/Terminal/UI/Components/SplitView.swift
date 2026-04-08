//
//  GhostySplitView.swift
//  aizen
//
//  Copied from Ghostty's SplitView implementation
//

import SwiftUI

enum SplitViewDirection: Codable {
    case horizontal, vertical
}

struct SplitView<L: View, R: View>: View {
    let direction: SplitViewDirection
    let dividerColor: Color
    let resizeIncrements: NSSize
    let left: L
    let right: R
    let onEqualize: () -> Void
    let minSize: CGFloat = 10

    @Binding var split: CGFloat
    private let splitterVisibleSize: CGFloat = 1
    private let splitterInvisibleSize: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let leftRect = self.leftRect(for: geo.size)
            let rightRect = self.rightRect(for: geo.size, leftRect: leftRect)
            let splitterPoint = self.splitterPoint(for: geo.size, leftRect: leftRect)

            // Use HStack/VStack instead of ZStack+offset so that embedded
            // NSViewRepresentable children (terminal surfaces) get correct
            // AppKit frames for hit-testing.  ZStack+offset only applies a
            // visual transform, leaving all NSView frames at (0,0).
            splitStack(leftRect: leftRect, rightRect: rightRect)

            // Divider overlay — positioned independently on top.
            SplitDivider(
                direction: direction,
                visibleSize: splitterVisibleSize,
                invisibleSize: splitterInvisibleSize,
                color: dividerColor,
                split: $split
            )
            .position(splitterPoint)
            .gesture(dragGesture(geo.size))
            .onTapGesture(count: 2) {
                onEqualize()
            }
        }
    }

    @ViewBuilder
    private func splitStack(leftRect: CGRect, rightRect: CGRect) -> some View {
        switch direction {
        case .horizontal:
            HStack(spacing: 0) {
                left.frame(width: leftRect.size.width, height: leftRect.size.height)
                Spacer(minLength: 0)
                right.frame(width: rightRect.size.width, height: rightRect.size.height)
            }
        case .vertical:
            VStack(spacing: 0) {
                left.frame(width: leftRect.size.width, height: leftRect.size.height)
                Spacer(minLength: 0)
                right.frame(width: rightRect.size.width, height: rightRect.size.height)
            }
        }
    }

    init(
        _ direction: SplitViewDirection,
        _ split: Binding<CGFloat>,
        dividerColor: Color = Color(nsColor: .separatorColor),
        resizeIncrements: NSSize = .init(width: 1, height: 1),
        @ViewBuilder left: (() -> L),
        @ViewBuilder right: (() -> R),
        onEqualize: @escaping () -> Void = {}
    ) {
        self.direction = direction
        self._split = split
        self.dividerColor = dividerColor
        self.resizeIncrements = resizeIncrements
        self.left = left()
        self.right = right()
        self.onEqualize = onEqualize
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                switch direction {
                case .horizontal:
                    let new = min(max(minSize, gesture.location.x), size.width - minSize)
                    split = new / size.width

                case .vertical:
                    let new = min(max(minSize, gesture.location.y), size.height - minSize)
                    split = new / size.height
                }
            }
    }

    private func leftRect(for size: CGSize) -> CGRect {
        var result = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch direction {
        case .horizontal:
            result.size.width *= split
            result.size.width -= splitterVisibleSize / 2
            result.size.width -= result.size.width.truncatingRemainder(dividingBy: self.resizeIncrements.width)

        case .vertical:
            result.size.height *= split
            result.size.height -= splitterVisibleSize / 2
            result.size.height -= result.size.height.truncatingRemainder(dividingBy: self.resizeIncrements.height)
        }

        return result
    }

    private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
        var result = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch direction {
        case .horizontal:
            result.origin.x += leftRect.size.width
            result.origin.x += splitterVisibleSize / 2
            result.size.width -= result.origin.x

        case .vertical:
            result.origin.y += leftRect.size.height
            result.origin.y += splitterVisibleSize / 2
            result.size.height -= result.origin.y
        }

        return result
    }

    private func splitterPoint(for size: CGSize, leftRect: CGRect) -> CGPoint {
        switch direction {
        case .horizontal:
            return CGPoint(x: leftRect.size.width, y: size.height / 2)

        case .vertical:
            return CGPoint(x: size.width / 2, y: leftRect.size.height)
        }
    }
}
