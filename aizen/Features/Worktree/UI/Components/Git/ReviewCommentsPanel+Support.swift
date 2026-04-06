import SwiftUI

extension ReviewCommentsPanel {
    func formatSingleComment(_ comment: ReviewComment, filePath: String) -> String {
        """
        \(filePath):\(comment.displayLineNumber)
        ```
        \(comment.codeContext)
        ```
        \(comment.comment)
        """
    }

    func lineTypeBadge(_ type: DiffLineType) -> some View {
        Group {
            if type == .header || type.marker.isEmpty {
                EmptyView()
            } else {
                Text(type.marker)
                    .foregroundStyle(type.markerColor)
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
    }

    @ViewBuilder
    func cardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: shape)
                shape
                    .fill(.white.opacity(0.03))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
