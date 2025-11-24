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
    let minSize: CGFloat = 10

    @Binding var split: CGFloat

    private let splitterVisibleSize: CGFloat = 1
    private let splitterInvisibleSize: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let metrics = layoutMetrics(for: geo.size)

            ZStack(alignment: .topLeading) {
                left
                    .frame(width: metrics.left.size.width, height: metrics.left.size.height)
                    .offset(x: metrics.left.origin.x, y: metrics.left.origin.y)
                right
                    .frame(width: metrics.right.size.width, height: metrics.right.size.height)
                    .offset(x: metrics.right.origin.x, y: metrics.right.origin.y)
                Divider(
                    direction: direction,
                    visibleSize: splitterVisibleSize,
                    invisibleSize: splitterInvisibleSize,
                    color: dividerColor,
                    split: $split,
                    axisLength: direction == .horizontal ? geo.size.height : geo.size.width
                )
                .position(metrics.splitterPoint)
                .gesture(dragGesture(geo.size, splitterPoint: metrics.splitterPoint))
            }
            .clipped() // Ensure subviews don't draw outside their allocated rect
        }
    }

    init(
        _ direction: SplitViewDirection,
        _ split: Binding<CGFloat>,
        dividerColor: Color = Color(nsColor: .separatorColor),
        resizeIncrements: NSSize = .init(width: 1, height: 1),
        @ViewBuilder left: (() -> L),
        @ViewBuilder right: (() -> R)
    ) {
        self.direction = direction
        self._split = split
        self.dividerColor = dividerColor
        self.resizeIncrements = resizeIncrements
        self.left = left()
        self.right = right()
    }

    private func dragGesture(_ size: CGSize, splitterPoint: CGPoint) -> some Gesture {
        return DragGesture()
            .onChanged { gesture in
                // Disable animations during drag to prevent flicker
                var transaction = Transaction()
                transaction.disablesAnimations = true

                withTransaction(transaction) {
                    switch (direction) {
                    case .horizontal:
                        let new = min(max(minSize, gesture.location.x), size.width - minSize)
                        split = new / size.width

                    case .vertical:
                        let new = min(max(minSize, gesture.location.y), size.height - minSize)
                        split = new / size.height
                    }
                }
            }
    }

    // MARK: - Layout helpers (pixel-aligned)
    private func layoutMetrics(for size: CGSize) -> (left: CGRect, right: CGRect, splitterPoint: CGPoint) {
        var leftRect = CGRect(origin: .zero, size: size)
        var rightRect = CGRect(origin: .zero, size: size)
        var point = CGPoint(x: size.width / 2, y: size.height / 2)

        switch (direction) {
        case .horizontal:
            let divider = splitterVisibleSize
            var leftWidth = size.width * split - divider / 2
            leftWidth = min(max(minSize, leftWidth), size.width - divider - minSize)

            leftRect.size.width = leftWidth
            leftRect.size.height = size.height

            rightRect.origin.x = leftWidth + divider
            rightRect.size.width = size.width - rightRect.origin.x
            rightRect.size.height = size.height

            point = CGPoint(x: leftWidth + divider / 2, y: size.height / 2)

        case .vertical:
            let divider = splitterVisibleSize
            var topHeight = size.height * split - divider / 2
            topHeight = min(max(minSize, topHeight), size.height - divider - minSize)

            leftRect.size.height = topHeight
            leftRect.size.width = size.width

            rightRect.origin.y = topHeight + divider
            rightRect.size.height = size.height - rightRect.origin.y
            rightRect.size.width = size.width

            point = CGPoint(x: size.width / 2, y: topHeight + divider / 2)
        }

        return (left: leftRect, right: rightRect, splitterPoint: point)
    }

    struct Divider: View {
        let direction: SplitViewDirection
        let visibleSize: CGFloat
        let invisibleSize: CGFloat
        let color: Color
        @Binding var split: CGFloat
        let axisLength: CGFloat

        private var visibleWidth: CGFloat? {
            switch (direction) {
            case .horizontal: return visibleSize
            case .vertical: return axisLength
            }
        }

        private var visibleHeight: CGFloat? {
            switch (direction) {
            case .horizontal: return axisLength
            case .vertical: return visibleSize
            }
        }

        private var invisibleWidth: CGFloat? {
            switch (direction) {
            case .horizontal: return visibleSize + invisibleSize
            case .vertical: return axisLength
            }
        }

        private var invisibleHeight: CGFloat? {
            switch (direction) {
            case .horizontal: return axisLength
            case .vertical: return visibleSize + invisibleSize
            }
        }

        var body: some View {
            ZStack {
                Color.clear
                    .frame(width: invisibleWidth, height: invisibleHeight)
                    .contentShape(Rectangle())
                Rectangle()
                    .fill(color)
                    .frame(width: visibleWidth, height: visibleHeight)
            }
            .onHover { isHovered in
                if (isHovered) {
                    switch (direction) {
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
