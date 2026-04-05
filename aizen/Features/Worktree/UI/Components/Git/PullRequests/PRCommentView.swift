import SwiftUI

struct PRCommentView: View {
    let comment: PRComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("@\(comment.author)")
                        .font(.system(size: 12, weight: .semibold))

                    if comment.isReview, let state = comment.reviewState {
                        reviewBadge(for: state)
                    }

                    Spacer()

                    Text(comment.relativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                MessageContentView(content: comment.body)

                if let path = comment.path {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text(path)
                        if let line = comment.line {
                            Text(":\(line)")
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var bubbleBackground: some View {
        Color.clear
            .background(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(GitWindowDividerStyle.color(opacity: 0.3), lineWidth: 0.5)
            }
    }

    private var avatarView: some View {
        let size: CGFloat = 28
        return Group {
            if let avatarURL = comment.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsAvatar
                    }
                }
            } else {
                initialsAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(GitWindowDividerStyle.color(opacity: 0.3), lineWidth: 0.5)
        )
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
            Text(initials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var initials: String {
        let trimmed = comment.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }

        let parts = trimmed
            .replacingOccurrences(of: "@", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" || $0 == "_" })

        if let first = parts.first?.first, let second = parts.dropFirst().first?.first {
            return String([first, second]).uppercased()
        }

        if let first = parts.first?.first {
            return String(first).uppercased()
        }

        return "?"
    }

    @ViewBuilder
    private func reviewBadge(for state: PRComment.ReviewState) -> some View {
        let color = foregroundColor(for: state)
        TagBadge(
            text: state.displayName,
            color: color,
            cornerRadius: 4,
            font: .system(size: 10, weight: .medium),
            horizontalPadding: 6,
            verticalPadding: 2,
            backgroundOpacity: 0.2,
            textColor: color,
            iconSystemName: iconName(for: state),
            iconSize: 9,
            spacing: 3
        )
    }

    private func iconName(for state: PRComment.ReviewState) -> String {
        switch state {
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "xmark.circle.fill"
        case .commented: return "bubble.left.fill"
        case .pending: return "clock.fill"
        }
    }

    private func foregroundColor(for state: PRComment.ReviewState) -> Color {
        switch state {
        case .approved: return .green
        case .changesRequested: return .red
        case .commented: return .blue
        case .pending: return .orange
        }
    }
}
