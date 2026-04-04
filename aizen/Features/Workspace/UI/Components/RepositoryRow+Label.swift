import SwiftUI

extension RepositoryRow {
    var activeSessionCount: Int {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.reduce(0) { total, worktree in
            guard !worktree.isDeleted else { return total }

            let chatCount = ((worktree.chatSessions as? Set<ChatSession>) ?? [])
                .filter { !$0.isDeleted }
                .count
            let terminalCount = ((worktree.terminalSessions as? Set<TerminalSession>) ?? [])
                .filter { !$0.isDeleted }
                .count
            let browserCount = ((worktree.browserSessions as? Set<BrowserSession>) ?? [])
                .filter { !$0.isDeleted }
                .count

            return total + chatCount + terminalCount + browserCount
        }
    }

    var sessionIndicatorColor: Color {
        isSelected ? selectedForegroundColor.opacity(0.9) : .secondary
    }

    var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var repositoryLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .symbolRenderingMode(isSelected ? .monochrome : .palette)
                .foregroundStyle(isSelected ? selectedForegroundColor : repositoryStatus.color, .secondary)
                .imageScale(.medium)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name ?? String(localized: "workspace.repository.unknown"))
                    .font(.body)
                    .foregroundStyle(isSelected ? selectedForegroundColor : Color.primary)
                    .lineLimit(1)

                if let note = repository.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(
                            isSelected
                                ? selectedForegroundColor.opacity(0.75)
                                : Color.secondary.opacity(0.7)
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if activeSessionCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(activeSessionCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(sessionIndicatorColor)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    var selectionBackground: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectionFillColor)
            }
        }
    }
}
