import SwiftUI

struct SplitDivider: View {
    let direction: SplitViewDirection
    let visibleSize: CGFloat
    let invisibleSize: CGFloat
    let color: Color
    @Binding var split: CGFloat

    private var visibleWidth: CGFloat? {
        switch direction {
        case .horizontal:
            return visibleSize
        case .vertical:
            return nil
        }
    }

    private var visibleHeight: CGFloat? {
        switch direction {
        case .horizontal:
            return nil
        case .vertical:
            return visibleSize
        }
    }

    private var invisibleWidth: CGFloat? {
        switch direction {
        case .horizontal:
            return visibleSize + invisibleSize
        case .vertical:
            return nil
        }
    }

    private var invisibleHeight: CGFloat? {
        switch direction {
        case .horizontal:
            return nil
        case .vertical:
            return visibleSize + invisibleSize
        }
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

    var body: some View {
        pointerStyled(
            ZStack {
                Color.clear
                    .frame(width: invisibleWidth, height: invisibleHeight)
                    .contentShape(Rectangle())
                Rectangle()
                    .fill(color)
                    .frame(width: visibleWidth, height: visibleHeight)
            }
        )
    }
}
